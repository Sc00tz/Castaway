//! Schema migrations: numbered SQL files in `rust-api/migrations`, applied in order when the
//! server starts. Applied versions are recorded in `castaway_migrations`.
//!
//! A database built by the old PinePods-era Python migrations (its `schema_migrations` table
//! at the final version, 118) already matches the baseline, so it's adopted as-is: versions 1
//! and 2 are recorded as applied without running them.

use argon2::PasswordHasher;
use sqlx::PgConnection;
use tracing::info;

use crate::error::{AppError, AppResult};

struct Migration {
    version: i32,
    name: &'static str,
    sql: &'static str,
}

const MIGRATIONS: &[Migration] = &[
    Migration { version: 1, name: "baseline", sql: include_str!("../../migrations/0001_baseline.sql") },
    Migration { version: 2, name: "seed", sql: include_str!("../../migrations/0002_seed.sql") },
    Migration { version: 3, name: "podcast_index_key", sql: include_str!("../../migrations/0003_podcast_index_key.sql") },
    Migration { version: 4, name: "drop_podpeople", sql: include_str!("../../migrations/0004_drop_podpeople.sql") },
    Migration { version: 5, name: "drop_ai", sql: include_str!("../../migrations/0005_drop_ai.sql") },
    Migration { version: 6, name: "castaway_sync_labels", sql: include_str!("../../migrations/0006_castaway_sync_labels.sql") },
];

/// The last migration version of the old Python runner.
const PINEPODS_FINAL_VERSION: &str = "118";
/// Versions a database at [`PINEPODS_FINAL_VERSION`] already has.
const ADOPTED_VERSIONS: i32 = 2;
/// Keeps two servers starting at once from migrating the same database together.
const LOCK_KEY: i64 = 7_283_111;

pub async fn run(pool: &sqlx::PgPool) -> AppResult<()> {
    let mut conn = pool.acquire().await?;
    sqlx::query("SELECT pg_advisory_lock($1)").bind(LOCK_KEY).execute(&mut *conn).await?;
    let result = apply(&mut conn).await;
    let _ = sqlx::query("SELECT pg_advisory_unlock($1)").bind(LOCK_KEY).execute(&mut *conn).await;
    result
}

async fn apply(conn: &mut PgConnection) -> AppResult<()> {
    sqlx::raw_sql(
        "CREATE TABLE IF NOT EXISTS castaway_migrations (
             version INTEGER PRIMARY KEY,
             name TEXT NOT NULL,
             applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
         )",
    )
    .execute(&mut *conn)
    .await?;
    let mut applied: Vec<i32> = sqlx::query_scalar("SELECT version FROM castaway_migrations").fetch_all(&mut *conn).await?;

    if applied.is_empty() && adopt_pinepods_database(conn).await? {
        applied = (1..=ADOPTED_VERSIONS).collect();
    }

    for m in MIGRATIONS.iter().filter(|m| !applied.contains(&m.version)) {
        info!("Applying database migration {:04} ({})", m.version, m.name);
        let sql = if m.version == 2 { seed_sql(m.sql)? } else { m.sql.to_string() };
        let mut tx = sqlx::Connection::begin(&mut *conn).await?;
        sqlx::raw_sql(sqlx::AssertSqlSafe(sql)).execute(&mut *tx).await?;
        sqlx::query("INSERT INTO castaway_migrations (version, name) VALUES ($1, $2)")
            .bind(m.version)
            .bind(m.name)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
    }
    Ok(())
}

/// Records the baseline as applied on a database the old Python migrations brought up to date.
/// Returns false when there's no such database (a fresh install).
async fn adopt_pinepods_database(conn: &mut PgConnection) -> AppResult<bool> {
    let legacy: Option<String> =
        sqlx::query_scalar("SELECT to_regclass('public.schema_migrations')::text").fetch_one(&mut *conn).await?;
    if legacy.is_none() {
        return Ok(false);
    }
    let current: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)")
        .bind(PINEPODS_FINAL_VERSION)
        .fetch_one(&mut *conn)
        .await?;
    if !current {
        return Err(AppError::Config(format!(
            "This database was set up by an older PinePods version. Upgrade it with PinePods first \
             (schema version {PINEPODS_FINAL_VERSION}), then start Castaway on it."
        )));
    }
    for m in MIGRATIONS.iter().filter(|m| m.version <= ADOPTED_VERSIONS) {
        sqlx::query("INSERT INTO castaway_migrations (version, name) VALUES ($1, $2)")
            .bind(m.version)
            .bind(m.name)
            .execute(&mut *conn)
            .await?;
    }
    info!("Adopted an existing PinePods database (schema version {PINEPODS_FINAL_VERSION})");
    Ok(true)
}

/// The seed migration with this install's secrets filled in. Every generated value is made of
/// characters that can't end an SQL string literal.
fn seed_sql(template: &str) -> AppResult<String> {
    use rand::RngExt;
    const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut rng = rand::rng();
    let api_key: String = (0..64).map(|_| CHARSET[rng.random_range(0..CHARSET.len())] as char).collect();
    // The background-tasks user never signs in with a password; this one is random and discarded.
    let password: String = (0..48).map(|_| CHARSET[rng.random_range(0..CHARSET.len())] as char).collect();
    let password_hash = argon2::Argon2::default()
        .hash_password(password.as_bytes())
        .map_err(|e| AppError::internal(&format!("Failed to hash the background-tasks password: {e}")))?
        .to_string();
    let encryption_key = fernet::Fernet::generate_key();
    for value in [&api_key, &password_hash, &encryption_key] {
        if value.contains('\'') {
            return Err(AppError::internal("Generated a seed value that isn't SQL-safe"));
        }
    }
    Ok(template
        .replace("__CASTAWAY_TASKS_API_KEY__", &api_key)
        .replace("__CASTAWAY_TASKS_PASSWORD_HASH__", &password_hash)
        .replace("__CASTAWAY_ENCRYPTION_KEY__", &encryption_key))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seed_fills_every_placeholder() {
        let sql = seed_sql(MIGRATIONS[1].sql).unwrap();
        for token in ["__CASTAWAY_TASKS_API_KEY__", "__CASTAWAY_TASKS_PASSWORD_HASH__", "__CASTAWAY_ENCRYPTION_KEY__"] {
            assert!(MIGRATIONS[1].sql.contains(token), "{token} missing from the seed");
            assert!(!sql.contains(token), "{token} left unfilled");
        }
    }

    #[test]
    fn migrations_are_numbered_in_order() {
        for (i, m) in MIGRATIONS.iter().enumerate() {
            assert_eq!(m.version, i as i32 + 1);
        }
    }
}
