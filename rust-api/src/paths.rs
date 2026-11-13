//! Where the server keeps files. The defaults are the container's layout; `CASTAWAY_DATA_DIR`
//! and `CASTAWAY_WEB_ROOT` move them, which lets tests run without touching those locations.

fn data_dir() -> String {
    crate::env::var("DATA_DIR").unwrap_or_else(|| "/data".to_string())
}

fn web_root() -> String {
    crate::env::var("WEB_ROOT").unwrap_or_else(|| "/var/www/html".to_string())
}

pub fn downloads_dir() -> String {
    format!("{}/downloads", data_dir())
}

pub fn youtube_downloads_dir() -> String {
    format!("{}/downloads/youtube", data_dir())
}

pub fn backups_dir() -> String {
    format!("{}/backups", data_dir())
}

pub fn local_media_dir() -> String {
    format!("{}/local-media", data_dir())
}

pub fn translations_dir() -> String {
    format!("{}/static/translations", web_root())
}

pub fn logo_file() -> String {
    format!("{}/static/assets/favicon.png", web_root())
}
