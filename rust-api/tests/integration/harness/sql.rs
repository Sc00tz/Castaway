//! Raw SQL helpers for tests that seed or inspect rows the API doesn't expose (migration
//! tests, refresh internals).

use pinepods_api::database::DatabasePool;

use super::TestApp;

/// Run `sql` on the test database (PostgreSQL, table names double-quoted). Only inline
/// literals, no binds.
pub async fn exec(app: &TestApp, sql: &str) {
    match app.db() {
        DatabasePool::Postgres(pool) => {
            sqlx::raw_sql(sqlx::AssertSqlSafe(sql.to_string())).execute(pool).await.unwrap_or_else(|e| panic!("{sql}: {e}"));
        }
    }
}

/// First column of the first row as an integer (counts, ids, booleans), None for SQL NULL / no row.
pub async fn int(app: &TestApp, sql: &str) -> Option<i64> {
    use sqlx::Row;
    fn get<R: Row>(row: &R) -> Option<i64>
    where
        usize: sqlx::ColumnIndex<R>,
        i64: for<'r> sqlx::Decode<'r, R::Database> + sqlx::Type<R::Database>,
        i32: for<'r> sqlx::Decode<'r, R::Database> + sqlx::Type<R::Database>,
        bool: for<'r> sqlx::Decode<'r, R::Database> + sqlx::Type<R::Database>,
    {
        if let Ok(v) = row.try_get::<Option<i64>, _>(0) {
            return v;
        }
        if let Ok(v) = row.try_get::<Option<i32>, _>(0) {
            return v.map(i64::from);
        }
        row.try_get::<Option<bool>, _>(0).unwrap().map(i64::from)
    }
    match app.db() {
        DatabasePool::Postgres(pool) => sqlx::query(sqlx::AssertSqlSafe(sql.to_string()))
            .fetch_optional(pool)
            .await
            .unwrap_or_else(|e| panic!("{sql}: {e}"))
            .and_then(|r| get(&r)),
    }
}

/// First column of the first row as text, None for SQL NULL / no row.
pub async fn text(app: &TestApp, sql: &str) -> Option<String> {
    use sqlx::Row;
    match app.db() {
        DatabasePool::Postgres(pool) => sqlx::query(sqlx::AssertSqlSafe(sql.to_string()))
            .fetch_optional(pool)
            .await
            .unwrap_or_else(|e| panic!("{sql}: {e}"))
            .and_then(|r| r.try_get::<Option<String>, _>(0).unwrap()),
    }
}

/// Apply `assignments` (e.g. "LastRefreshAttempt = '2000-01-01 00:00:00'") to a podcast's refresh
/// state, which lives on its feed and, until those columns go, the podcast row.
pub async fn set_refresh_state(app: &TestApp, podcast_id: i32, assignments: &str) {
    exec(app, &format!(r#"UPDATE "Podcasts" SET {assignments} WHERE PodcastID = {podcast_id}"#)).await;
    exec(
        app,
        &format!(r#"UPDATE "Feeds" SET {assignments} WHERE FeedID = (SELECT FeedID FROM "Podcasts" WHERE PodcastID = {podcast_id})"#),
    )
    .await;
}

/// Set when a podcast's feed is refreshed next, e.g. '2000-01-01 00:00:00' to make it due now.
pub async fn set_next_refresh(app: &TestApp, podcast_id: i32, at: &str) {
    set_refresh_state(app, podcast_id, &format!("NextRefreshAt = '{at}'")).await;
}
