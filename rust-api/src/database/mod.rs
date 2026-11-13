//! Database access. Every query is a method on `DatabasePool`; the methods are split by area
//! into the submodules below, with shared types and helpers kept here.

use sqlx::{Pool, Postgres, Row};
use std::time::Duration;
use crate::{config::{Config, OIDCConfig}, error::{AppError, AppResult}};
use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use lazy_static::lazy_static;
use base64;
use tracing::{debug, info, warn};

pub mod dialect;
pub mod migrate;
use dialect::{dialect_fn, dialect_match, dialect_method};

mod auth;
mod mfa;
mod oidc;
mod users;
mod user_settings;
mod server_settings;
mod podcasts;
mod podcast_settings;
mod episodes;
mod queue;
mod saved;
mod history;
mod stats;
mod home;
mod playlists;
mod collections;
mod refresh;
mod feed_parsing;
mod notifications;
mod in_app_notifications;
pub use in_app_notifications::StoredInAppNotification;
mod downloads;
mod transcripts;
pub use transcripts::{TranscriptMatch, TranscriptSearchEpisode};
mod youtube;
mod rss;
mod gpodder;
mod backup;
mod shared_episodes;
mod recommendations;
mod local_podcasts;

pub use mfa::*;
pub use oidc::*;
pub use users::*;
pub use user_settings::*;
pub(crate) use podcasts::*;
pub use queue::*;
pub use playlists::*;
pub use refresh::*;
pub(crate) use notifications::*;
pub use gpodder::*;
pub use backup::*;

#[derive(Clone)]
pub enum DatabasePool {
    Postgres(Pool<Postgres>),
}

/// A transaction rolled back because it collided with a concurrent one: a deadlock or
/// serialization failure. Running it again is safe.
fn is_write_conflict(e: &AppError) -> bool {
    let AppError::Database(sqlx::Error::Database(db)) = e else { return false };
    matches!(db.code().as_deref(), Some("40001") | Some("40P01"))
}

/// Connects to the configured database, waiting up to `DB_WAIT_TIMEOUT` seconds (default 120)
/// for the server to come up, and creating the database if it doesn't exist yet.
async fn connect_creating_database(
    options: sqlx::postgres::PgConnectOptions,
    max_connections: u32,
    min_connections: u32,
) -> AppResult<Pool<Postgres>> {
    let wait = std::env::var("DB_WAIT_TIMEOUT").ok().and_then(|v| v.trim().parse().ok()).unwrap_or(120u64);
    let deadline = std::time::Instant::now() + Duration::from_secs(wait);
    let connect = |options: sqlx::postgres::PgConnectOptions| {
        sqlx::postgres::PgPoolOptions::new()
            .max_connections(max_connections)
            .min_connections(min_connections)
            .acquire_timeout(Duration::from_secs(30))
            .connect_with(options)
    };
    let mut created = false;
    loop {
        match connect(options.clone()).await {
            Ok(pool) => return Ok(pool),
            // 3D000: database doesn't exist. Create it from the maintenance database.
            Err(sqlx::Error::Database(e)) if e.code().as_deref() == Some("3D000") && !created => {
                let name = options.get_database().unwrap_or_default().to_string();
                tracing::info!("Creating database {name}");
                let admin = connect(options.clone().database("postgres")).await?;
                let quoted = format!("\"{}\"", name.replace('"', "\"\""));
                sqlx::raw_sql(sqlx::AssertSqlSafe(format!("CREATE DATABASE {quoted}"))).execute(&admin).await?;
                admin.close().await;
                created = true;
            }
            Err(e @ (sqlx::Error::Io(_) | sqlx::Error::PoolTimedOut | sqlx::Error::Tls(_)))
                if std::time::Instant::now() < deadline =>
            {
                tracing::info!("Waiting for the database: {e}");
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
            // 57P03: the server is starting up.
            Err(sqlx::Error::Database(e)) if e.code().as_deref() == Some("57P03") && std::time::Instant::now() < deadline => {
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
            Err(e) => return Err(e.into()),
        }
    }
}

/// `Users.GpodderUrl` of users on the Castaway gpodder server. Not a real address any more;
/// clients and the UI read it as "internal".
pub const INTERNAL_GPODDER_URL: &str = "http://localhost:8042";

impl DatabasePool {
    /// Identifies the database this pool points at (for in-process state kept per database).
    pub fn instance_key(&self) -> String {
        dialect_match!(self, {
            pg(pool) => {
                let o = pool.connect_options();
                format!("pg:{}:{}/{}", o.get_host(), o.get_port(), o.get_database().unwrap_or_default())
            },
        })
    }

    pub async fn new(config: &Config) -> AppResult<Self> {
        let db = &config.database;
        // A DB_HOST beginning with '/' is treated as a Unix domain socket
        // directory rather than a TCP hostname (e.g. /var/run/postgresql).
        let host_is_socket = db.host.starts_with('/');

        let mut options = sqlx::postgres::PgConnectOptions::new()
            .username(&db.username)
            .password(&db.password)
            .database(&db.name)
            // Port is still relevant for sockets: PG names the socket
            // file `.s.PGSQL.<port>`.
            .port(db.port);
        options = if host_is_socket {
            options.socket(&db.host)
        } else {
            options.host(&db.host)
        };

        let pool = connect_creating_database(options, db.max_connections, db.min_connections).await?;
        Ok(DatabasePool::Postgres(pool))
    }

    /// Brings the schema up to date (see [`migrate`]).
    pub async fn migrate(&self) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => migrate::run(pool).await,
        })
    }

    pub async fn health_check(&self) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query("SELECT 1 as health")
                    .fetch_one(pool)
                    .await?;
                let health: i32 = row.try_get("health")?;
                Ok(health == 1)
            },
        })
    }

    // Helper function to parse categories JSON string into HashMap - matches Python version
    fn parse_categories_json(&self, categories_str: &str) -> Option<std::collections::HashMap<String, String>> {
        if categories_str.is_empty() {
            return Some(std::collections::HashMap::new());
        }
        
        if categories_str.starts_with('{') {
            // Try to parse as JSON first
            if let Ok(parsed) = serde_json::from_str::<std::collections::HashMap<String, String>>(categories_str) {
                return Some(clean_categories(parsed));
            }
        } else {
            // Fall back to comma-separated parsing like Python version.
            // Skip empty segments so blank/whitespace categories aren't created.
            let mut result = std::collections::HashMap::new();
            for cat in categories_str.split(',') {
                let trimmed = cat.trim();
                if trimmed.is_empty() {
                    continue;
                }
                result.insert(result.len().to_string(), trimmed.to_string());
            }
            return Some(clean_categories(result));
        }
        
        // Return empty map if parsing fails
        Some(std::collections::HashMap::new())
    }
}
