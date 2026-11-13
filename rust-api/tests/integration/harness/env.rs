//! Process-wide test environment: where the throwaway PostgreSQL and Valkey servers live, the migrated template database every test clones, and the sandboxed network.
//!
//! Initialised exactly once per test process (tests run in parallel threads, and nextest
//! may run them in parallel *processes* — template creation is guarded by a server-side lock
//! so both work).

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use sqlx::{Connection, Executor, PgConnection};

use super::fixtures::FixtureServer;

pub struct TestEnv {
    pub db_host: String,
    pub db_port: u16,
    pub db_user: String,
    pub db_password: String,
    pub valkey_host: String,
    pub valkey_port: u16,
    /// Name of the fully-migrated database every test clones.
    pub template: String,
    pub fixtures: FixtureServer,
    /// Where the yt-dlp stub and its answers live (see `youtube.rs`).
    pub ytdlp_dir: PathBuf,
}

static ENV: OnceLock<TestEnv> = OnceLock::new();

fn var(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_string())
}

pub fn env() -> &'static TestEnv {
    ENV.get_or_init(|| {
        // Built on a dedicated thread with its own runtime: callers are inside a
        // #[tokio::test] runtime that may not allow blocking.
        std::thread::spawn(init)
            .join()
            .unwrap_or_else(|_| panic!("integration test environment failed to initialise (see output above)"))
    })
}

fn init() -> TestEnv {
    sandbox_network();
    pinepods_api::services::url_guard::allow_loopback_for_tests();
    let ytdlp_dir = std::env::temp_dir().join(format!("pinepods-ytdlp-{}", std::process::id()));
    super::youtube::install_stub(&ytdlp_dir);
    super::files::install_sandbox();

    let mut env = TestEnv {
        db_host: var("PINEPODS_TEST_DB_HOST", "127.0.0.1"),
        db_port: var("PINEPODS_TEST_DB_PORT", "55433").parse().expect("PINEPODS_TEST_DB_PORT"),
        db_user: var("PINEPODS_TEST_DB_USER", "pinepods"),
        db_password: var("PINEPODS_TEST_DB_PASSWORD", "testpass"),
        valkey_host: var("PINEPODS_TEST_VALKEY_HOST", "127.0.0.1"),
        valkey_port: var("PINEPODS_TEST_VALKEY_PORT", "56380").parse().expect("PINEPODS_TEST_VALKEY_PORT"),
        template: String::new(),
        fixtures: FixtureServer::start(),
        ytdlp_dir,
    };

    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    env.template = rt.block_on(ensure_template(&env));
    env
}

/// Make every outbound HTTP request from the server fail fast unless it targets the local
/// fixture server. reqwest honours these variables when a client is built, so set them
/// before any `AppState` exists. Port 9 (discard) on loopback refuses instantly.
fn sandbox_network() {
    for (k, v) in [
        ("HTTP_PROXY", "http://127.0.0.1:9"),
        ("HTTPS_PROXY", "http://127.0.0.1:9"),
        ("ALL_PROXY", "http://127.0.0.1:9"),
        ("http_proxy", "http://127.0.0.1:9"),
        ("https_proxy", "http://127.0.0.1:9"),
        ("all_proxy", "http://127.0.0.1:9"),
        ("NO_PROXY", "127.0.0.1,localhost"),
        ("no_proxy", "127.0.0.1,localhost"),
    ] {
        // SAFETY (edition 2021 API): runs once, before the server code under test starts
        // any threads that read the environment.
        std::env::set_var(k, v);
    }
}

pub fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

/// The template is named after a hash of the migrations, so editing one transparently
/// produces (and caches) a fresh template.
fn schema_fingerprint() -> String {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("migrations");
    let mut files: Vec<_> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().path()).collect();
    files.sort();
    let mut h = DefaultHasher::new();
    for f in files {
        std::fs::read(&f).unwrap_or_else(|e| panic!("read {}: {e}", f.display())).hash(&mut h);
    }
    format!("{:012x}", h.finish() & 0xffff_ffff_ffff)
}

fn not_running_hint(env: &TestEnv, err: impl std::fmt::Display) -> String {
    format!(
        "cannot reach the test PostgreSQL server at {}:{} ({err}).\n\
         Start the throwaway services with `rust-api/scripts/integration-tests.sh` (which also runs \
         the suite), or `docker compose -f rust-api/tests/docker-compose.yml up -d --wait`.",
        env.db_host, env.db_port
    )
}

pub fn pg_url(env: &TestEnv, db: &str) -> String {
    format!(
        "postgres://{}:{}@{}:{}/{}",
        env.db_user, env.db_password, env.db_host, env.db_port, db
    )
}

async fn ensure_template(env: &TestEnv) -> String {
    let name = format!("pinepods_tmpl_{}", schema_fingerprint());
    let mut conn = PgConnection::connect(&pg_url(env, "postgres"))
        .await
        .unwrap_or_else(|e| panic!("{}", not_running_hint(env, e)));
    conn.execute("SELECT pg_advisory_lock(7283110)").await.unwrap();
    let exists = sqlx::query("SELECT 1 FROM pg_database WHERE datname = $1")
        .bind(&name)
        .fetch_optional(&mut conn)
        .await
        .unwrap()
        .is_some();
    if !exists {
        let building = format!("{name}_building");
        conn.execute(sqlx::AssertSqlSafe(format!(r#"DROP DATABASE IF EXISTS "{building}" WITH (FORCE)"#)))
            .await
            .unwrap();
        conn.execute(sqlx::AssertSqlSafe(format!(r#"CREATE DATABASE "{building}""#))).await.unwrap();
        run_migrations(env, &building).await;
        // Publish atomically so a half-migrated template is never cloned.
        conn.execute(sqlx::AssertSqlSafe(format!(r#"ALTER DATABASE "{building}" RENAME TO "{name}""#)))
            .await
            .unwrap();
    }
    conn.execute("SELECT pg_advisory_unlock(7283110)").await.unwrap();
    name
}

/// Run the server's own migrations into `db_name`, exactly as a fresh install does.
pub async fn run_migrations(env: &TestEnv, db_name: &str) {
    eprintln!("[harness] migrating template database {db_name}");
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(1)
        .connect(&pg_url(env, db_name))
        .await
        .unwrap_or_else(|e| panic!("{}", not_running_hint(env, e)));
    pinepods_api::database::migrate::run(&pool)
        .await
        .unwrap_or_else(|e| panic!("schema migrations failed for template {db_name}: {e:?}"));
    pool.close().await;
}

/// Shared helper for per-test databases: connect to the server's maintenance database.
pub async fn admin_pg(env: &TestEnv) -> PgConnection {
    PgConnection::connect(&pg_url(env, "postgres")).await.expect("connect postgres admin")
}
