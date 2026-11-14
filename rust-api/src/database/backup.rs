//! Backup, restore and scheduled backups.

use super::*;

// A single enabled scheduled-backup row, used by the background scheduler to decide
// when a backup is due. retention_count: None/0 = keep all backups.
#[derive(Debug, Clone)]
pub struct ScheduledBackupRow {
    pub user_id: i32,
    pub cron_schedule: String,
    pub retention_count: Option<i32>,
    pub last_run: Option<DateTime<Utc>>,
}

// A data dump lists every table, empty or not; EpisodeIDAliases only exists once episodes are
// shared between users.
pub(super) async fn dump_has_shared_episodes(path: &std::path::Path) -> AppResult<bool> {
    use tokio::io::AsyncBufReadExt;
    let file = tokio::fs::File::open(path)
        .await
        .map_err(|e| AppError::internal(&format!("Failed to open backup file: {}", e)))?;
    let mut lines = tokio::io::BufReader::new(file).lines();
    while let Some(line) = lines.next_line().await.map_err(|e| AppError::internal(&format!("Failed to read backup file: {}", e)))? {
        if line.contains(r#""EpisodeIDAliases""#) || line.contains("`EpisodeIDAliases`") {
            return Ok(true);
        }
    }
    Ok(false)
}

/// Strip the trailing `\r`/`\n` from a raw line read with `read_until(b'\n')`.
pub(super) fn trim_line_eol(line: &[u8]) -> &[u8] {
    let mut end = line.len();
    while end > 0 && (line[end - 1] == b'\n' || line[end - 1] == b'\r') {
        end -= 1;
    }
    &line[..end]
}

/// True for the lone `\.` line that terminates a Postgres `COPY ... FROM stdin` data block.
pub(super) fn is_pg_copy_terminator(line: &[u8]) -> bool {
    trim_line_eol(line) == b"\\."
}

/// Stream a Postgres plain-text dump from `reader` to `writer`, dropping the `COPY` data
/// blocks for any table in `skip_tables`. Everything else is passed through byte-for-byte.
///
/// Works line-by-line (bounded memory) with a small state machine so that data rows which
/// happen to start with the text `COPY` are never mistaken for statement-level COPY headers:
/// once inside a COPY block we only watch for its `\.` terminator. Table names are matched as
/// the exact double-quoted identifier pg_dump emits (`"Sessions"`), so `"Sessions"` does not
/// match inside `"GpodderSessions"`.
pub(super) async fn stream_pg_dump_skipping_tables<R, W>(
    reader: R,
    writer: &mut W,
    skip_tables: &[&str],
) -> std::io::Result<()>
where
    R: tokio::io::AsyncRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin,
{
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    enum CopyState {
        Normal,
        Pass,
        Skip,
    }

    let needles: Vec<String> = skip_tables.iter().map(|t| format!("\"{}\"", t)).collect();
    let mut buf_reader = BufReader::new(reader);
    let mut state = CopyState::Normal;
    let mut line: Vec<u8> = Vec::new();

    loop {
        line.clear();
        if buf_reader.read_until(b'\n', &mut line).await? == 0 {
            break;
        }
        match state {
            CopyState::Normal => {
                let mut drop_line = false;
                if line.starts_with(b"COPY ") {
                    let header = String::from_utf8_lossy(&line);
                    if header.contains(" FROM stdin;") {
                        if needles.iter().any(|n| header.contains(n.as_str())) {
                            state = CopyState::Skip;
                            drop_line = true; // drop the COPY header for skipped tables
                        } else {
                            state = CopyState::Pass;
                        }
                    }
                }
                if !drop_line {
                    writer.write_all(&line).await?;
                }
            }
            CopyState::Pass => {
                writer.write_all(&line).await?;
                if is_pg_copy_terminator(&line) {
                    state = CopyState::Normal;
                }
            }
            CopyState::Skip => {
                if is_pg_copy_terminator(&line) {
                    state = CopyState::Normal;
                }
                // drop every line inside a skipped COPY block, including the terminator
            }
        }
    }
    Ok(())
}

impl DatabasePool {

    // Backup user data - matches Python backup_user function exactly
    pub async fn backup_user(&self, user_id: i32) -> AppResult<String> {
        let podcasts = dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(
                    r#"SELECT podcastname, feedurl FROM "Podcasts" WHERE userid = $1 AND (username IS NULL OR username = '') AND (password IS NULL OR password = '')"#
                )
                .bind(user_id)
                .fetch_all(pool)
                .await?;

                let mut podcasts = Vec::new();
                for row in rows {
                    podcasts.push((
                        row.try_get::<String, _>("podcastname")?,
                        row.try_get::<String, _>("feedurl")?,
                    ));
                }
                podcasts
            },
        });

        // Generate OPML content
        let mut opml_content = String::from(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Podcast Subscriptions</title>
  </head>
  <body>
"#
        );

        for (podcast_name, feed_url) in podcasts {
            // Escape XML characters in podcast name and feed URL
            let escaped_name = podcast_name
                .replace('&', "&amp;")
                .replace('<', "&lt;")
                .replace('>', "&gt;")
                .replace('"', "&quot;")
                .replace('\'', "&#39;");
            
            let escaped_url = feed_url
                .replace('&', "&amp;")
                .replace('<', "&lt;")
                .replace('>', "&gt;")
                .replace('"', "&quot;");

            opml_content.push_str(&format!(
                r#"    <outline text="{}" title="{}" type="rss" xmlUrl="{}" />
"#,
                escaped_name, escaped_name, escaped_url
            ));
        }

        opml_content.push_str("  </body>\n</opml>");
        Ok(opml_content)
    }

    // Add more database operations as needed...

    // Restore server data from an on-disk SQL dump, streaming the file into the
    // psql client so memory usage stays bounded regardless of dump size.
    //
    // Postgres restores are fully atomic: the truncate + data load run inside a single
    // psql transaction (--single-transaction + ON_ERROR_STOP), so a failure rolls back
    // and leaves the pre-restore data untouched. Crucially, MVCC means concurrent app
    // connections keep seeing the old committed data until COMMIT, so the database never
    // appears empty mid-restore (which previously triggered the "create first user" flow
    // and a write race that corrupted the restore).
    pub async fn restore_server_data_from_path(&self, path: &std::path::Path) -> AppResult<()> {

        // Transient auth tables that hold only disposable login tokens. They are never worth
        // restoring, and historically their schema has drifted (e.g. an upgraded instance can
        // still carry the legacy `Sessions(sessionid, userid, value, expire)` layout while a
        // fresh install has `Sessions(SessionID, UserID, SessionToken, ...)`). Restoring their
        // rows can therefore fail the column match and, under --single-transaction +
        // ON_ERROR_STOP, roll back the entire restore. We strip these tables' data from the
        // incoming dump so the rest of the (compatible) data still loads. GpodderSyncState is
        // deliberately NOT included here — it holds real per-device sync watermarks.
        const SKIP_TABLES: &[&str] = &["Sessions", "GpodderSessions"];

        use tokio::process::Command;
        use tokio::io::AsyncWriteExt;

        // Episodes are shared between users now; a backup from before that holds one copy of
        // each episode per user, which this schema can't take.
        if !dump_has_shared_episodes(path).await? {
            return Err(AppError::bad_request(
                "This backup is from a Castaway version before episodes were shared between users and can't be restored here",
            ));
        }

        dialect_match!(self, {
            pg(_) => {
                let host = std::env::var("DB_HOST").unwrap_or_else(|_| "localhost".to_string());
                let port = std::env::var("DB_PORT").unwrap_or_else(|_| "5432".to_string());
                let database = std::env::var("DB_NAME").unwrap_or_else(|_| "castaway".to_string());
                let username = std::env::var("DB_USER").unwrap_or_else(|_| "postgres".to_string());
                let password = std::env::var("DB_PASSWORD").unwrap_or_else(|_| "password".to_string());

                // Feed the whole restore through psql stdin as one transaction:
                //   1. disable FK/triggers for the load,
                //   2. truncate every table in the public schema,
                //   3. stream the data-only dump,
                //   4. re-enable triggers.
                // --single-transaction wraps it in BEGIN/COMMIT; ON_ERROR_STOP makes it
                // all-or-nothing (otherwise psql skips failing statements, exits 0, and
                // silently drops rows). The dump is streamed, so memory stays bounded.
                let mut cmd = Command::new("psql");
                cmd.arg("--host").arg(&host)
                   .arg("--port").arg(&port)
                   .arg("--username").arg(&username)
                   .arg("--no-password")
                   .arg("--dbname").arg(&database)
                   .arg("--quiet")
                   .arg("--single-transaction")
                   .arg("-v").arg("ON_ERROR_STOP=1")
                   .env("PGPASSWORD", &password)
                   .stdin(std::process::Stdio::piped())
                   .stdout(std::process::Stdio::piped())
                   .stderr(std::process::Stdio::piped());

                let mut child = cmd.spawn()
                    .map_err(|e| AppError::internal(&format!("Failed to start psql: {}", e)))?;

                const PREAMBLE: &str = "SET session_replication_role = replica;\n\
                    DO $$ DECLARE r RECORD; BEGIN \
                    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP \
                    EXECUTE format('TRUNCATE TABLE %I RESTART IDENTITY CASCADE', r.tablename); \
                    END LOOP; END $$;\n";
                const POSTAMBLE: &str = "\nSET session_replication_role = DEFAULT;\n";

                // psql writes to stdout/stderr (sequence setval rows, NOTICE/COPY messages)
                // as it consumes stdin. If we wrote the whole dump and only drained those pipes
                // afterward, a large restore would deadlock: psql blocks once its ~64KB output
                // pipe fills, stops reading stdin, and our writer blocks forever. So drain
                // stdin/stdout/stderr concurrently and only then reap the child.
                let mut stdin = child.stdin.take()
                    .ok_or_else(|| AppError::internal("psql stdin was not piped"))?;
                let mut stdout = child.stdout.take()
                    .ok_or_else(|| AppError::internal("psql stdout was not piped"))?;
                let mut stderr_pipe = child.stderr.take()
                    .ok_or_else(|| AppError::internal("psql stderr was not piped"))?;

                let path_buf = path.to_path_buf();
                let writer = async move {
                    stdin.write_all(PREAMBLE.as_bytes()).await
                        .map_err(|e| AppError::internal(&format!("Failed to write restore preamble: {}", e)))?;
                    let file = tokio::fs::File::open(&path_buf).await
                        .map_err(|e| AppError::internal(&format!("Failed to open backup file: {}", e)))?;
                    // Stream the dump through, dropping COPY blocks for the transient session
                    // tables so a legacy/mismatched `Sessions` schema can't abort the restore.
                    stream_pg_dump_skipping_tables(file, &mut stdin, SKIP_TABLES).await
                        .map_err(|e| AppError::internal(&format!("Failed to stream SQL to psql: {}", e)))?;
                    stdin.write_all(POSTAMBLE.as_bytes()).await
                        .map_err(|e| AppError::internal(&format!("Failed to write restore postamble: {}", e)))?;
                    stdin.shutdown().await
                        .map_err(|e| AppError::internal(&format!("Failed to close psql stdin: {}", e)))?;
                    Ok::<(), AppError>(())
                };

                use tokio::io::AsyncReadExt;
                let read_out = async move {
                    let mut buf = Vec::new();
                    let _ = stdout.read_to_end(&mut buf).await;
                    buf
                };
                let read_err = async move {
                    let mut buf = Vec::new();
                    let _ = stderr_pipe.read_to_end(&mut buf).await;
                    buf
                };

                let (write_res, _out, err_buf) = tokio::join!(writer, read_out, read_err);

                let status = child.wait().await
                    .map_err(|e| AppError::internal(&format!("Failed to wait for psql: {}", e)))?;

                let stderr = String::from_utf8_lossy(&err_buf);
                if !status.success() {
                    // psql's own error (e.g. ON_ERROR_STOP) is more useful than a broken-pipe
                    // write error, so report stderr/status here regardless of the writer result.
                    return Err(AppError::internal(&format!("psql restore failed (rolled back): {}", stderr.trim())));
                }
                // psql exited clean; surface a writer error only if one slipped through.
                write_res?;
                if !stderr.trim().is_empty() {
                    tracing::warn!("psql restore reported messages: {}", stderr.trim());
                }
                tracing::info!("psql restore completed successfully");
            },
        });

        Ok(())
    }


    // Set scheduled backup configuration. retention_count: None/Some(0) = keep all backups.
    pub async fn set_scheduled_backup(&self, user_id: i32, cron_schedule: &str, enabled: bool, retention_count: Option<i32>) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"
                    INSERT INTO "ScheduledBackups" (userid, cron_schedule, enabled, retention_count, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, NOW(), NOW())
                    ON CONFLICT (userid)
                    DO UPDATE SET
                        cron_schedule = EXCLUDED.cron_schedule,
                        enabled = EXCLUDED.enabled,
                        retention_count = EXCLUDED.retention_count,
                        updated_at = NOW()
                "#)
                .bind(user_id)
                .bind(cron_schedule)
                .bind(enabled)
                .bind(retention_count)
                .execute(pool)
                .await?;
            },
        });
        Ok(())
    }

    // Get scheduled backup configuration
    pub async fn get_scheduled_backup(&self, user_id: i32) -> AppResult<serde_json::Value> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT cron_schedule, enabled, retention_count, created_at, updated_at
                    FROM "ScheduledBackups"
                    WHERE userid = $1
                "#)
                .bind(user_id)
                .fetch_optional(pool)
                .await?;

                if let Some(row) = row {
                    Ok(serde_json::json!({
                        "schedule": row.get::<String, _>("cron_schedule"),
                        "enabled": row.get::<bool, _>("enabled"),
                        "retention_count": row.get::<Option<i32>, _>("retention_count"),
                        "created_at": row.get::<chrono::NaiveDateTime, _>("created_at").format("%Y-%m-%dT%H:%M:%S").to_string(),
                        "updated_at": row.get::<chrono::NaiveDateTime, _>("updated_at").format("%Y-%m-%dT%H:%M:%S").to_string()
                    }))
                } else {
                    Ok(serde_json::json!({
                        "schedule": null,
                        "enabled": false,
                        "retention_count": null,
                        "created_at": null,
                        "updated_at": null
                    }))
                }
            },
        })
    }

    // Get all enabled scheduled backups (used by the background scheduler to decide what is due)
    pub async fn get_enabled_scheduled_backups(&self) -> AppResult<Vec<ScheduledBackupRow>> {
        let mut backups = Vec::new();
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(r#"
                    SELECT userid, cron_schedule, retention_count, last_run
                    FROM "ScheduledBackups"
                    WHERE enabled = TRUE
                "#)
                .fetch_all(pool)
                .await?;

                for row in rows {
                    backups.push(ScheduledBackupRow {
                        user_id: row.get::<i32, _>("userid"),
                        cron_schedule: row.get::<String, _>("cron_schedule"),
                        retention_count: row.get::<Option<i32>, _>("retention_count"),
                        last_run: row.get::<Option<chrono::NaiveDateTime>, _>("last_run")
                            .map(|dt| DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc)),
                    });
                }
            },
        });
        Ok(backups)
    }

    // Record the time the scheduler last ran a given user's scheduled backup
    pub async fn update_scheduled_backup_last_run(&self, user_id: i32, ts: DateTime<Utc>) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"UPDATE "ScheduledBackups" SET last_run = $1 WHERE userid = $2"#)
                    .bind(ts.naive_utc())
                    .bind(user_id)
                    .execute(pool)
                    .await?;
            },
        });
        Ok(())
    }

    // Execute backup to file (called by scheduler)
    pub async fn execute_scheduled_backup(&self, _user_id: i32) -> AppResult<String> {
        use tokio::process::Command;
        use chrono::Utc;

        // Generate backup filename with timestamp
        let timestamp = Utc::now().format("%Y%m%d_%H%M%S");
        let backup_filename = format!("scheduled_backup_{}.sql", timestamp);
        let backup_path = format!("{}/{}", crate::paths::backups_dir(), backup_filename);

        // Ensure backup directory exists (matches manual_backup_to_directory)
        if let Err(e) = std::fs::create_dir_all(crate::paths::backups_dir()) {
            return Err(AppError::internal(&format!("Failed to create backup directory: {}", e)));
        }


        // Get database password from environment
        let db_password = std::env::var("DB_PASSWORD")
            .map_err(|_| AppError::internal("Database password not found in environment"))?;

        dialect_match!(self, {
            pg(_) => {
                let db_host = std::env::var("DB_HOST").unwrap_or_else(|_| "localhost".to_string());
                let db_port = std::env::var("DB_PORT").unwrap_or_else(|_| "5432".to_string());
                let db_user = std::env::var("DB_USER").unwrap_or_else(|_| "postgres".to_string());
                let db_name = std::env::var("DB_NAME").unwrap_or_else(|_| "castaway".to_string());

                // Use the same restore-safe flags as manual_backup_to_directory so the
                // resulting dump can be cleanly restored via `psql -f`.
                let mut cmd = Command::new("pg_dump");
                cmd.arg("-h").arg(&db_host)
                   .arg("-p").arg(&db_port)
                   .arg("-U").arg(&db_user)
                   .arg("-d").arg(&db_name)
                   .arg("--clean")
                   .arg("--if-exists")
                   .arg("--no-owner")
                   .arg("--no-privileges")
                   // Transient login-token tables: excluded for security and to avoid
                   // cross-version schema drift on restore.
                   .arg("--exclude-table-data=public.\"Sessions\"")
                   .arg("--exclude-table-data=public.\"GpodderSessions\"")
                   .arg("-f").arg(&backup_path)
                   .env("PGPASSWORD", &db_password);

                let output = cmd.output().await
                    .map_err(|e| AppError::internal(&format!("Failed to execute backup: {}", e)))?;

                if !output.status.success() {
                    let error_msg = String::from_utf8_lossy(&output.stderr);
                    return Err(AppError::internal(&format!("Backup failed: {}", error_msg)));
                }
            },
        });

        Ok(backup_filename)
    }
}

#[cfg(test)]
mod restore_filter_tests {
    use super::stream_pg_dump_skipping_tables;

    async fn run_pg(input: &str, skip: &[&str]) -> String {
        let mut out: Vec<u8> = Vec::new();
        stream_pg_dump_skipping_tables(input.as_bytes(), &mut out, skip)
            .await
            .unwrap();
        String::from_utf8(out).unwrap()
    }

    #[tokio::test]
    async fn pg_strips_skipped_table_copy_block_and_keeps_others() {
        let input = concat!(
            "SET something = 1;\n",
            "COPY public.\"Podcasts\" (id, title) FROM stdin;\n",
            "1\tHello\n",
            "2\tCOPY public.\"Sessions\" looks like a header but is data\n",
            "\\.\n",
            "COPY public.\"Sessions\" (sessionid, userid, value, expire) FROM stdin;\n",
            "1\t2\tsecret\t1234\n",
            "\\.\n",
            "COPY public.\"Episodes\" (id) FROM stdin;\n",
            "9\n",
            "\\.\n",
        );
        let out = run_pg(input, &["Sessions", "GpodderSessions"]).await;
        // Podcasts block preserved verbatim, including the data row that starts with COPY.
        assert!(out.contains("COPY public.\"Podcasts\" (id, title) FROM stdin;"));
        assert!(out.contains("2\tCOPY public.\"Sessions\" looks like a header but is data"));
        // Episodes block preserved.
        assert!(out.contains("COPY public.\"Episodes\" (id) FROM stdin;"));
        assert!(out.contains("\n9\n"));
        // Sessions header + data fully removed.
        assert!(!out.contains("sessionid, userid, value, expire"));
        assert!(!out.contains("1\t2\tsecret\t1234"));
    }

    #[tokio::test]
    async fn pg_does_not_match_substring_table_name() {
        let input = concat!(
            "COPY public.\"GpodderSyncState\" (id) FROM stdin;\n",
            "1\n",
            "\\.\n",
        );
        let out = run_pg(input, &["Sessions"]).await;
        // "Sessions" must not match inside "GpodderSyncState"/"GpodderSessions".
        assert!(out.contains("GpodderSyncState"));
        assert!(out.contains("\n1\n"));
    }

}
