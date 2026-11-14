//! The server's own schema migrations: a fresh install, a restart, and adopting a database the
//! old PinePods-era migrations built.

use sqlx::{Executor, PgPool};

use crate::harness::env;

/// A new, empty database for one test, dropped by the returned guard.
struct ScratchDb {
    name: String,
    pool: PgPool,
}

impl ScratchDb {
    async fn new(label: &str) -> ScratchDb {
        let env = env::env();
        let name = format!("mig_{label}_{:x}", std::process::id());
        let mut admin = env::admin_pg(env).await;
        admin.execute(sqlx::AssertSqlSafe(format!(r#"DROP DATABASE IF EXISTS "{name}" WITH (FORCE)"#))).await.unwrap();
        admin.execute(sqlx::AssertSqlSafe(format!(r#"CREATE DATABASE "{name}""#))).await.unwrap();
        let pool = PgPool::connect(&env::pg_url(env, &name)).await.unwrap();
        ScratchDb { name, pool }
    }

    async fn versions(&self) -> Vec<i32> {
        sqlx::query_scalar("SELECT version FROM castaway_migrations ORDER BY version").fetch_all(&self.pool).await.unwrap()
    }

    async fn count(&self, table: &str) -> i64 {
        sqlx::query_scalar(sqlx::AssertSqlSafe(format!(r#"SELECT COUNT(*) FROM "{table}""#))).fetch_one(&self.pool).await.unwrap()
    }

    async fn drop(self) {
        self.pool.close().await;
        let mut admin = env::admin_pg(env::env()).await;
        let _ = admin.execute(sqlx::AssertSqlSafe(format!(r#"DROP DATABASE IF EXISTS "{}" WITH (FORCE)"#, self.name))).await;
    }
}

const BASELINE: &str = include_str!("../../migrations/0001_baseline.sql");

/// Every migration version, in order (one numbered file each).
fn all_versions() -> Vec<i32> {
    let count = std::fs::read_dir(concat!(env!("CARGO_MANIFEST_DIR"), "/migrations"))
        .unwrap()
        .filter(|e| e.as_ref().unwrap().path().extension().is_some_and(|x| x == "sql"))
        .count();
    (1..=count as i32).collect()
}

#[tokio::test]
async fn a_fresh_database_gets_the_schema_and_its_own_secrets() {
    let a = ScratchDb::new("fresh_a").await;
    let b = ScratchDb::new("fresh_b").await;
    for db in [&a, &b] {
        castaway_api::database::migrate::run(&db.pool).await.unwrap();
        assert_eq!(db.versions().await, all_versions());
        assert_eq!(db.count("Playlists").await, 7, "the system playlists are seeded");
        let user: String = sqlx::query_scalar(r#"SELECT username FROM "Users" WHERE userid = 1"#).fetch_one(&db.pool).await.unwrap();
        assert_eq!(user, "background_tasks");
    }
    let key = |db: &ScratchDb| {
        let pool = db.pool.clone();
        async move {
            let api: String = sqlx::query_scalar(r#"SELECT apikey FROM "APIKeys" WHERE userid = 1"#).fetch_one(&pool).await.unwrap();
            let enc: String = sqlx::query_scalar(r#"SELECT encryptionkey FROM "AppSettings""#).fetch_one(&pool).await.unwrap();
            (api, enc)
        }
    };
    let (ka, kb) = (key(&a).await, key(&b).await);
    assert_eq!(ka.0.len(), 64);
    assert_ne!(ka, kb, "every install generates its own keys");
    assert!(fernet::Fernet::new(&ka.1).is_some(), "the encryption key is a valid Fernet key");

    // Starting again changes nothing.
    castaway_api::database::migrate::run(&a.pool).await.unwrap();
    assert_eq!(a.versions().await, all_versions());
    assert_eq!(a.count("Playlists").await, 7);
    a.drop().await;
    b.drop().await;
}

#[tokio::test]
async fn a_current_pinepods_database_is_adopted_without_reseeding() {
    let db = ScratchDb::new("adopt").await;
    sqlx::raw_sql(BASELINE).execute(&db.pool).await.unwrap();
    sqlx::raw_sql(
        r#"CREATE TABLE schema_migrations (version VARCHAR(10) PRIMARY KEY, name TEXT, checksum VARCHAR(64));
           INSERT INTO schema_migrations (version, name, checksum) VALUES ('117', 'x', 'x'), ('118', 'y', 'y');
           INSERT INTO "Users" (fullname, username, email, hashed_pw, isadmin) VALUES ('Old Admin', 'oldadmin', 'a@b.c', 'x', TRUE);
           INSERT INTO "GpodderDevices" (userid, devicename, systemrole)
             SELECT userid, 'pinepods', 'pinepods' FROM "Users" WHERE username = 'oldadmin';
           INSERT INTO "GpodderSyncEpisodeActions" (userid, podcasturl, episodeurl, action, "timestamp", serverts, origin)
             SELECT userid, 'https://a/feed', 'https://a/1.mp3', 'play', 1, 1, 'pinepods' FROM "Users" WHERE username = 'oldadmin';"#,
    )
    .execute(&db.pool)
    .await
    .unwrap();

    castaway_api::database::migrate::run(&db.pool).await.unwrap();
    assert_eq!(db.versions().await, all_versions(), "the baseline is adopted, later migrations run");
    assert_eq!(db.count("Users").await, 1, "the existing data is kept and nothing is seeded on top");
    assert_eq!(db.count("Playlists").await, 0);
    let role: String = sqlx::query_scalar(r#"SELECT systemrole FROM "GpodderDevices""#).fetch_one(&db.pool).await.unwrap();
    let origin: String = sqlx::query_scalar(r#"SELECT origin FROM "GpodderSyncEpisodeActions""#).fetch_one(&db.pool).await.unwrap();
    assert_eq!((role.as_str(), origin.as_str()), ("castaway", "castaway"), "the server's own sync labels are renamed");
    db.drop().await;
}

#[tokio::test]
async fn the_old_internal_sync_device_gets_a_castaway_name() {
    let db = ScratchDb::new("devname").await;
    sqlx::raw_sql(BASELINE).execute(&db.pool).await.unwrap();
    // One user with only the old internal device; one who also already has a Castaway device.
    sqlx::raw_sql(
        r#"CREATE TABLE schema_migrations (version VARCHAR(10) PRIMARY KEY, name TEXT, checksum VARCHAR(64));
           INSERT INTO schema_migrations (version, name, checksum) VALUES ('118', 'y', 'y');
           INSERT INTO "Users" (fullname, username, email, hashed_pw, isadmin) VALUES
             ('One', 'one', 'one@b.c', 'x', TRUE), ('Two', 'two', 'two@b.c', 'x', FALSE);
           INSERT INTO "GpodderDevices" (userid, devicename, devicecaption)
             SELECT userid, 'pinepods-internal-' || userid, 'PinePods' FROM "Users";
           INSERT INTO "GpodderDevices" (userid, devicename, systemrole)
             SELECT userid, 'castaway', 'pinepods' FROM "Users" WHERE username = 'two';
           INSERT INTO "GpodderDevices" (userid, devicename, devicecaption)
             SELECT userid, 'pinepods-server', 'PinePods server' FROM "Users" WHERE username = 'two';
           UPDATE "Users" SET defaultgpodderdevice = 'pinepods-server' WHERE username = 'two';
           INSERT INTO "SyncTargets" (userid, kind, url, encryptedsecret, devicename, needsfullsync)
             SELECT userid, 'gpodder', 'https://gpodder.example', 'x', 'pinepods', FALSE FROM "Users" WHERE username = 'two';"#,
    )
    .execute(&db.pool)
    .await
    .unwrap();

    castaway_api::database::migrate::run(&db.pool).await.unwrap();
    let devices: Vec<(String, String, Option<String>, Option<String>)> = sqlx::query_as(
        r#"SELECT u.username, d.devicename, d.systemrole, d.devicecaption FROM "GpodderDevices" d
           JOIN "Users" u ON u.userid = d.userid ORDER BY u.username, d.systemrole NULLS LAST"#,
    )
    .fetch_all(&db.pool)
    .await
    .unwrap();
    for (_, name, role, caption) in &devices {
        let shown = format!("{name} {} {}", role.as_deref().unwrap_or(""), caption.as_deref().unwrap_or(""));
        assert!(!shown.to_lowercase().contains("pinepods"), "a sync app would show {shown:?}");
    }
    assert_eq!(devices[0].0, "one");
    assert_eq!((devices[0].1.as_str(), devices[0].2.as_deref()), ("castaway", Some("castaway")), "the old device becomes the Castaway device");
    let two: Vec<_> = devices.iter().filter(|d| d.0 == "two").collect();
    assert_eq!(two.len(), 3);
    assert!(two.iter().any(|d| d.1 == "castaway-server" && d.3.as_deref() == Some("Castaway server")), "{two:?}");
    let default: Option<String> =
        sqlx::query_scalar(r#"SELECT defaultgpodderdevice FROM "Users" WHERE username = 'two'"#).fetch_one(&db.pool).await.unwrap();
    assert_eq!(default.as_deref(), Some("castaway-server"), "the default device follows its new name");
    let (target, full): (Option<String>, bool) =
        sqlx::query_as(r#"SELECT devicename, needsfullsync FROM "SyncTargets""#).fetch_one(&db.pool).await.unwrap();
    assert_eq!((target.as_deref(), full), (Some("castaway"), true), "the sync server sees a new device, so everything is sent again");
    assert_eq!(two.iter().filter(|d| d.2.as_deref() == Some("castaway")).count(), 1, "still one Castaway device");
    db.drop().await;
}

#[tokio::test]
async fn an_older_pinepods_database_is_refused() {
    let db = ScratchDb::new("old").await;
    sqlx::raw_sql(
        "CREATE TABLE schema_migrations (version VARCHAR(10) PRIMARY KEY, name TEXT, checksum VARCHAR(64));
         INSERT INTO schema_migrations (version, name, checksum) VALUES ('090', 'x', 'x');",
    )
    .execute(&db.pool)
    .await
    .unwrap();

    let err = castaway_api::database::migrate::run(&db.pool).await.unwrap_err();
    assert!(format!("{err:?}").contains("older schema than Castaway can take over"), "{err:?}");
    let tables: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM castaway_migrations").fetch_one(&db.pool).await.unwrap();
    assert_eq!(tables, 0, "nothing is recorded");
    db.drop().await;
}
