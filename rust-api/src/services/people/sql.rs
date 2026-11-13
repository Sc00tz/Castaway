//! Small query helpers for the people (hosts and guests) store.
//!
//! Queries are plain PostgreSQL text with `$1, $2, ...` placeholders.

/// A runtime-built bind list, for queries whose placeholder count depends on the input
/// (multi-row inserts, `IN (...)` lists). Pass it as `dyn binds` in place of `[...]`.
#[derive(Debug, Clone)]
pub enum Bind {
    Int(i32),
    BigInt(i64),
    Text(Option<String>),
    Bool(bool),
    Ts(chrono::NaiveDateTime),
}

macro_rules! bind_all {
    ($q:expr, [$($b:expr),* $(,)?]) => { $q$(.bind($b))* };
    ($q:expr, dyn $binds:expr) => {{
        let mut q = $q;
        for b in $binds.iter().cloned() {
            q = match b {
                $crate::services::people::sql::Bind::Int(v) => q.bind(v),
                $crate::services::people::sql::Bind::BigInt(v) => q.bind(v),
                $crate::services::people::sql::Bind::Text(v) => q.bind(v),
                $crate::services::people::sql::Bind::Bool(v) => q.bind(v),
                $crate::services::people::sql::Bind::Ts(v) => q.bind(v),
            };
        }
        q
    }};
}

/// `fetch_all!(db, sql, [binds...], |row| expr)` -> `Vec<T>` (propagates errors with `?`).
/// `row` is a `&PgRow`; read columns through [`RowExt`].
macro_rules! fetch_all {
    (@go $db:expr, $sql:expr, ($($binds:tt)*), |$row:ident| $map:expr) => {{
        #[allow(unused_imports)]
        use $crate::services::people::sql::RowExt as _;
        match $db {
            $crate::database::DatabasePool::Postgres(pool) => {
                let q = sqlx::query(sqlx::AssertSqlSafe($sql.to_string()));
                let rows = $crate::services::people::sql::bind_all!(q, $($binds)*).fetch_all(pool).await?;
                rows.iter().map(|$row| -> Result<_, sqlx::Error> { Ok($map) }).collect::<Result<Vec<_>, sqlx::Error>>()?
            }
        }
    }};
    ($db:expr, $sql:expr, dyn $binds:expr, |$row:ident| $map:expr) => {
        $crate::services::people::sql::fetch_all!(@go $db, $sql, (dyn $binds), |$row| $map)
    };
    ($db:expr, $sql:expr, $binds:tt, |$row:ident| $map:expr) => {
        $crate::services::people::sql::fetch_all!(@go $db, $sql, ($binds), |$row| $map)
    };
}

/// `fetch_optional!(db, sql, [binds...], |row| expr)` -> `Option<T>`.
macro_rules! fetch_optional {
    ($db:expr, $sql:expr, $($rest:tt)*) => {{
        let mut v = $crate::services::people::sql::fetch_all!($db, format!("{} LIMIT 1", $sql), $($rest)*);
        if v.is_empty() { None } else { Some(v.swap_remove(0)) }
    }};
}

/// `execute!(db, sql, [binds...])` -> rows affected.
macro_rules! execute {
    (@go $db:expr, $sql:expr, ($($binds:tt)*)) => {{
        match $db {
            $crate::database::DatabasePool::Postgres(pool) => {
                let q = sqlx::query(sqlx::AssertSqlSafe($sql.to_string()));
                $crate::services::people::sql::bind_all!(q, $($binds)*).execute(pool).await?.rows_affected()
            }
        }
    }};
    ($db:expr, $sql:expr, dyn $binds:expr) => {
        $crate::services::people::sql::execute!(@go $db, $sql, (dyn $binds))
    };
    ($db:expr, $sql:expr, $binds:tt) => {
        $crate::services::people::sql::execute!(@go $db, $sql, ($binds))
    };
}

pub(crate) use {bind_all, execute, fetch_all, fetch_optional};

/// Typed column reads that accept any integer width and NULLs.
pub trait RowExt {
    fn str(&self, col: &str) -> Result<String, sqlx::Error>;
    fn opt_str(&self, col: &str) -> Result<Option<String>, sqlx::Error>;
    fn int(&self, col: &str) -> Result<i64, sqlx::Error>;
    fn opt_int(&self, col: &str) -> Result<Option<i64>, sqlx::Error>;
    fn flag(&self, col: &str) -> Result<bool, sqlx::Error>;
    fn ts(&self, col: &str) -> Result<Option<chrono::NaiveDateTime>, sqlx::Error>;
}

macro_rules! row_ext {
    ($row:ty, $utc:expr) => {
        impl RowExt for $row {
            fn str(&self, col: &str) -> Result<String, sqlx::Error> {
                Ok(self.opt_str(col)?.unwrap_or_default())
            }
            fn opt_str(&self, col: &str) -> Result<Option<String>, sqlx::Error> {
                #[allow(unused_imports)]
                use sqlx::Row;
                self.try_get::<Option<String>, _>(col)
            }
            fn int(&self, col: &str) -> Result<i64, sqlx::Error> {
                Ok(self.opt_int(col)?.unwrap_or_default())
            }
            fn opt_int(&self, col: &str) -> Result<Option<i64>, sqlx::Error> {
                #[allow(unused_imports)]
                use sqlx::Row;
                match self.try_get::<Option<i64>, _>(col) {
                    Ok(v) => Ok(v),
                    Err(_) => match self.try_get::<Option<i32>, _>(col) {
                        Ok(v) => Ok(v.map(i64::from)),
                        Err(_) => self.try_get::<Option<i16>, _>(col).map(|v| v.map(i64::from)),
                    },
                }
            }
            fn flag(&self, col: &str) -> Result<bool, sqlx::Error> {
                #[allow(unused_imports)]
                use sqlx::Row;
                match self.try_get::<Option<bool>, _>(col) {
                    Ok(v) => Ok(v.unwrap_or(false)),
                    Err(_) => match self.try_get::<Option<i8>, _>(col) {
                        Ok(v) => Ok(v.unwrap_or(0) != 0),
                        Err(_) => self.opt_int(col).map(|v| v.unwrap_or(0) != 0),
                    },
                }
            }
            fn ts(&self, col: &str) -> Result<Option<chrono::NaiveDateTime>, sqlx::Error> {
                #[allow(unused_imports)]
                use sqlx::Row;
                match self.try_get::<Option<chrono::NaiveDateTime>, _>(col) {
                    Ok(v) => Ok(v),
                    Err(e) => {
                        if $utc {
                            self.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>(col).map(|v| v.map(|d| d.naive_utc()))
                        } else {
                            Err(e)
                        }
                    }
                }
            }
        }
    };
}

row_ext!(sqlx::postgres::PgRow, false);

/// `($1, $2, $3), ($4, $5, $6), ...` for a multi-row insert.
pub fn values_placeholders(rows: usize, cols: usize) -> String {
    (0..rows)
        .map(|r| {
            let cells: Vec<String> = (0..cols).map(|c| format!("${}", r * cols + c + 1)).collect();
            format!("({})", cells.join(", "))
        })
        .collect::<Vec<_>>()
        .join(", ")
}

/// `$1, $2, ...` for an `IN (...)` list starting at `$start`.
pub fn in_list(start: usize, n: usize) -> String {
    (0..n).map(|i| format!("${}", start + i)).collect::<Vec<_>>().join(", ")
}

