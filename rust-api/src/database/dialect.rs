//! Query helpers for PostgreSQL, Castaway's only database.
//!
//! [`dialect_match!`] unwraps the [`DatabasePool`](super::DatabasePool) and brings [`pg`] into
//! scope as `q`, so query code reads `q::query`, `q::query_as::<T>`, `q::query_scalar::<T>`,
//! `q::begin`, `q::Tx`, `q::Conn` and `q::Row`.

/// Runs `$body` with the PostgreSQL pool bound to `$pg` and [`pg`] in scope as `q`.
///
/// ```ignore
/// dialect_match!(self, {
///     pg(pool) => { q::query(r#"SELECT ... FROM "Users" WHERE userid = $1"#).bind(id).fetch_one(pool).await? },
/// })
/// ```
macro_rules! dialect_match {
    ($db:expr, { pg($pg:pat) => $pg_body:expr $(,)? }) => {
        match $db {
            $crate::database::DatabasePool::Postgres($pg) => {
                #[allow(unused_imports)]
                use $crate::database::dialect::pg as q;
                $pg_body
            }
        }
    };
}
pub(crate) use dialect_match;

/// A helper function with [`pg`] in scope as `q` (in the signature too).
macro_rules! dialect_fn {
    ([$name:ident] $(#[$m:meta])* $vis:vis async fn ($($params:tt)*) $(-> $ret:ty)? $body:block) => {
        $crate::database::dialect::dialect_fn!(@one $name, [$(#[$m])*] $vis [async] ($($params)*) [$($ret)?] $body);
    };
    ([$name:ident] $(#[$m:meta])* $vis:vis fn ($($params:tt)*) $(-> $ret:ty)? $body:block) => {
        $crate::database::dialect::dialect_fn!(@one $name, [$(#[$m])*] $vis [] ($($params)*) [$($ret)?] $body);
    };
    (@one $name:ident, [$($attr:tt)*] $vis:vis [$($async:tt)?] ($($params:tt)*) [$($ret:ty)?] $body:block) => {
        #[allow(non_snake_case, unused_imports)]
        mod $name {
            use super::*;
            use $crate::database::dialect::pg as q;
            $($attr)*
            pub $($async)? fn $name($($params)*) $(-> $ret)? $body
        }
        #[allow(unused_imports)]
        $vis use self::$name::$name;
    };
}
pub(crate) use dialect_fn;

/// [`dialect_fn!`] for methods on `DatabasePool`.
macro_rules! dialect_method {
    ([$name:ident] $(#[$m:meta])* $vis:vis async fn ($($params:tt)*) $(-> $ret:ty)? $body:block) => {
        #[allow(non_snake_case, unused_imports)]
        mod $name {
            use super::*;
            use $crate::database::dialect::pg as q;
            impl DatabasePool {
                $(#[$m])*
                pub(crate) async fn $name($($params)*) $(-> $ret)? $body
            }
        }
    };
}
pub(crate) use dialect_method;

/// PostgreSQL: plain sqlx.
pub mod pg {
    use sqlx::postgres::{PgArguments, PgRow};
    use sqlx::{FromRow, Postgres};

    pub type Db = Postgres;
    pub type Row = PgRow;
    pub type Conn = sqlx::PgConnection;
    pub type Tx<'c> = sqlx::Transaction<'c, Postgres>;
    pub type Pool = sqlx::Pool<Postgres>;

    pub fn query<'q>(sql: impl sqlx::SqlSafeStr) -> sqlx::query::Query<'q, Postgres, PgArguments> {
        sqlx::query(sql)
    }

    pub fn query_as<'q, O>(sql: impl sqlx::SqlSafeStr) -> sqlx::query::QueryAs<'q, Postgres, O, PgArguments>
    where
        O: for<'r> FromRow<'r, PgRow>,
    {
        sqlx::query_as(sql)
    }

    pub fn query_scalar<'q, O>(sql: impl sqlx::SqlSafeStr) -> sqlx::query::QueryScalar<'q, Postgres, O, PgArguments>
    where
        (O,): for<'r> FromRow<'r, PgRow>,
    {
        sqlx::query_scalar(sql)
    }

    pub async fn begin(pool: &Pool) -> Result<Tx<'static>, sqlx::Error> {
        pool.begin().await
    }

    /// The driver's own row, for helpers generic over `sqlx::Row`.
    pub fn raw(row: &Row) -> &Row {
        row
    }

    /// An `int[]` column.
    pub fn int_array(row: &Row, col: &str) -> Result<Option<Vec<i32>>, sqlx::Error> {
        use sqlx::Row as _;
        row.try_get(col)
    }

    /// A `numeric` column as a float.
    pub fn decimal(row: &Row, col: &str) -> Result<Option<f64>, sqlx::Error> {
        use bigdecimal::ToPrimitive;
        use sqlx::Row as _;
        Ok(row.try_get::<Option<bigdecimal::BigDecimal>, _>(col)?.and_then(|d| d.to_f64()))
    }
}
