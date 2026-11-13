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
        pinepods_api::database::migrate::run(&db.pool).await.unwrap();
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
    pinepods_api::database::migrate::run(&a.pool).await.unwrap();
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
           INSERT INTO "Users" (fullname, username, email, hashed_pw, isadmin) VALUES ('Old Admin', 'oldadmin', 'a@b.c', 'x', TRUE);"#,
    )
    .execute(&db.pool)
    .await
    .unwrap();

    pinepods_api::database::migrate::run(&db.pool).await.unwrap();
    assert_eq!(db.versions().await, all_versions(), "the baseline is adopted, later migrations run");
    assert_eq!(db.count("Users").await, 1, "the existing data is kept and nothing is seeded on top");
    assert_eq!(db.count("Playlists").await, 0);
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

    let err = pinepods_api::database::migrate::run(&db.pool).await.unwrap_err();
    assert!(format!("{err:?}").contains("older PinePods version"), "{err:?}");
    let tables: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM castaway_migrations").fetch_one(&db.pool).await.unwrap();
    assert_eq!(tables, 0, "nothing is recorded");
    db.drop().await;
}
