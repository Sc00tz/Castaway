//! Searching the stored transcripts of a user's episodes.

use super::DatabasePool;
use crate::database::dialect::dialect_match;
use crate::error::AppResult;
use crate::services::transcript_search::{websearch_query, Term};
use serde::Serialize;
#[allow(unused_imports)]
use sqlx::Row;

/// An episode whose transcript matched, in the shape the episode lists use.
#[derive(Debug, Clone, Default, Serialize, utoipa::ToSchema)]
pub struct TranscriptSearchEpisode {
    pub podcastid: i32,
    pub podcastname: String,
    pub artworkurl: String,
    pub author: String,
    pub feedurl: String,
    pub userid: i32,
    pub episodeid: i32,
    pub episodetitle: String,
    pub episodedescription: String,
    pub episodeurl: String,
    pub episodeartwork: String,
    /// `YYYY-MM-DDTHH:MM:SS`, empty when unknown.
    pub episodepubdate: String,
    pub episodeduration: i32,
    pub listenduration: i32,
    pub completed: bool,
    pub saved: bool,
    pub queued: bool,
    pub downloaded: bool,
    pub is_youtube: bool,
}

/// A matching transcript: its episode and the text to find the moments in.
pub struct TranscriptMatch {
    pub episode: TranscriptSearchEpisode,
    pub source: String,
    pub text: Option<String>,
    pub segments: Option<String>,
}

/// Matching rows ranked per episode: the newest transcript wins.
const PICK_ONE: &str = "ROW_NUMBER() OVER (PARTITION BY t.episodeid ORDER BY t.transcriptid DESC)";

fn pub_date(d: Option<chrono::NaiveDateTime>) -> String {
    d.map(|d| d.format("%Y-%m-%dT%H:%M:%S").to_string()).unwrap_or_default()
}

macro_rules! read_match {
    ($r:expr, $flag:expr) => {{
        let r = $r;
        TranscriptMatch {
            episode: TranscriptSearchEpisode {
                podcastid: r.try_get("podcastid")?,
                podcastname: r.try_get::<Option<String>, _>("podcastname")?.unwrap_or_default(),
                artworkurl: r.try_get::<Option<String>, _>("artworkurl")?.unwrap_or_default(),
                author: r.try_get::<Option<String>, _>("author")?.unwrap_or_default(),
                feedurl: r.try_get::<Option<String>, _>("feedurl")?.unwrap_or_default(),
                userid: r.try_get("userid")?,
                episodeid: r.try_get("episodeid")?,
                episodetitle: r.try_get::<Option<String>, _>("episodetitle")?.unwrap_or_default(),
                episodedescription: r.try_get::<Option<String>, _>("episodedescription")?.unwrap_or_default(),
                episodeurl: r.try_get::<Option<String>, _>("episodeurl")?.unwrap_or_default(),
                episodeartwork: r.try_get::<Option<String>, _>("episodeartwork")?.unwrap_or_default(),
                episodepubdate: pub_date(r.try_get("episodepubdate").ok().flatten()),
                episodeduration: r.try_get::<Option<i32>, _>("episodeduration")?.unwrap_or(0),
                listenduration: r.try_get::<Option<i32>, _>("listenduration").ok().flatten().unwrap_or(0),
                completed: $flag(&r, "completed"),
                saved: $flag(&r, "saved"),
                queued: $flag(&r, "queued"),
                downloaded: $flag(&r, "downloaded"),
                is_youtube: false,
            },
            source: r.try_get("source")?,
            text: r.try_get("transcripttext")?,
            segments: r.try_get("segments_text")?,
        }
    }};
}

impl DatabasePool {
    /// One page of the user's episodes whose transcripts match `terms`, newest first, and how
    /// many match in all, using PostgreSQL's full-text index.
    pub async fn search_transcripts(&self, user_id: i32, terms: &[Term], limit: i64, offset: i64) -> AppResult<(Vec<TranscriptMatch>, i64)> {
        if !terms.iter().any(|t| !t.negate) {
            return Ok((Vec::new(), 0));
        }
        let (rows, total) = dialect_match!(self, {
            pg(pool) => {
                let matches = "to_tsvector('simple', COALESCE(t.transcripttext, '')) @@ websearch_to_tsquery('simple', $4)".to_string();
                let binds: Vec<String> = vec![websearch_query(terms)];
                let sql = format!(r#"
                    SELECT p.podcastid, p.podcastname, p.artworkurl, p.author, p.feedurl, p.userid,
                           e.episodeid, e.episodetitle, e.episodedescription, e.episodeurl,
                           CASE
                               WHEN p.usepodcastcoverscustomized = TRUE AND p.usepodcastcovers = TRUE THEN p.artworkurl
                               WHEN u.usepodcastcovers = TRUE THEN p.artworkurl
                               ELSE e.episodeartwork
                           END AS episodeartwork,
                           e.episodepubdate, e.episodeduration,
                           COALESCE(h.listenduration, 0) AS listenduration,
                           COALESCE(ues.completed, FALSE) AS completed,
                           (se.episodeid IS NOT NULL) AS saved,
                           (eq.episodeid IS NOT NULL) AS queued,
                           (de.episodeid IS NOT NULL) AS downloaded,
                           t.source, t.transcripttext, t.segments::text AS segments_text,
                           COUNT(*) OVER() AS total_count
                    FROM (
                        SELECT t.transcriptid, t.episodeid, {PICK_ONE} AS rn
                        FROM "EpisodeTranscripts" t
                        WHERE t.status = 'complete' AND t.episodeid IN (
                            SELECT e2.episodeid FROM "Episodes" e2 JOIN "Podcasts" p2 ON p2.feedid = e2.feedid WHERE p2.userid = $1)
                          AND {matches}
                    ) m
                    JOIN "EpisodeTranscripts" t ON t.transcriptid = m.transcriptid
                    JOIN "Episodes" e ON e.episodeid = m.episodeid
                    JOIN "Podcasts" p ON p.feedid = e.feedid AND p.userid = $1
                    LEFT JOIN "Users" u ON u.userid = p.userid
                    LEFT JOIN "UserEpisodeHistory" h ON h.episodeid = e.episodeid AND h.userid = $1
                    LEFT JOIN "UserEpisodeState" ues ON ues.episodeid = e.episodeid AND ues.userid = $1
                    LEFT JOIN "SavedEpisodes" se ON se.episodeid = e.episodeid AND se.userid = $1
                    LEFT JOIN "EpisodeQueue" eq ON eq.episodeid = e.episodeid AND eq.userid = $1 AND eq.is_youtube = FALSE
                    LEFT JOIN "DownloadedEpisodes" de ON de.episodeid = e.episodeid AND de.userid = $1
                    WHERE m.rn = 1
                    ORDER BY e.episodepubdate DESC, e.episodeid DESC
                    LIMIT $2 OFFSET $3
                "#);
                let mut query = q::query(sqlx::AssertSqlSafe(sql)).bind(user_id).bind(limit).bind(offset);
                for b in binds {
                    query = query.bind(b);
                }
                let rows = query.fetch_all(pool).await?;
                let total = rows.first().map(|r| r.try_get::<i64, _>("total_count")).transpose()?.unwrap_or(0);
                let flag = |r: &q::Row, c: &str| r.try_get::<Option<bool>, _>(c).ok().flatten().unwrap_or(false);
                let mut out = Vec::with_capacity(rows.len());
                for r in rows {
                    out.push(read_match!(r, flag));
                }
                (out, total)
            },
        });
        Ok((rows, total))
    }

    /// How many of the user's episodes have a transcript that can be searched.
    pub async fn searchable_transcript_count(&self, user_id: i32) -> AppResult<i64> {
        Ok(dialect_match!(self, {
            pg(pool) => q::query_scalar::<i64>(r#"
                SELECT COUNT(DISTINCT t.episodeid) FROM "EpisodeTranscripts" t
                JOIN "Episodes" e ON e.episodeid = t.episodeid
                JOIN "Podcasts" p ON p.feedid = e.feedid
                WHERE p.userid = $1 AND t.status = 'complete' AND t.transcripttext IS NOT NULL
            "#)
            .bind(user_id)
            .fetch_one(pool)
            .await?,
        }))
    }
}
