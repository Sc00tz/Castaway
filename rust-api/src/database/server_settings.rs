//! Server-wide admin settings: downloads, self-service, email.

use super::*;

impl DatabasePool {
    // Get Castaway version - matches Python get_pinepods_version function
    pub async fn get_pinepods_version(&self) -> AppResult<String> {
        match std::fs::read_to_string("/pinepods/current_version") {
            Ok(version) => {
                let version = version.trim();
                if version.is_empty() {
                    Ok("dev_mode".to_string())
                } else {
                    Ok(version.to_string())
                }
            }
            Err(_) => Ok("Version file not found.".to_string()),
        }
    }

    // Enable/disable downloads - matches Python enable_disable_downloads function exactly
    pub async fn enable_disable_downloads(&self) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"UPDATE "AppSettings" SET downloadenabled = CASE WHEN downloadenabled = true THEN false ELSE true END"#)
                    .execute(pool)
                    .await?;
            },
        });
        Ok(())
    }

    // Enable/disable self service - matches Python enable_disable_self_service function exactly
    pub async fn enable_disable_self_service(&self) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"UPDATE "AppSettings" SET selfserviceuser = CASE WHEN selfserviceuser = true THEN false ELSE true END"#)
                    .execute(pool)
                    .await?;
            },
        });
        Ok(())
    }

    // Get download status - matches Python download_status function exactly
    pub async fn download_status(&self) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let result: Option<bool> = q::query_scalar(r#"SELECT downloadenabled FROM "AppSettings""#)
                    .fetch_optional(pool)
                    .await?;
                Ok(result.unwrap_or(false))
            },
        })
    }

    // Get the admin download-metadata settings (#451/#533/#658). Missing row or
    // NULLs fall back to the disabled/default set.
    pub async fn get_download_settings(&self) -> AppResult<crate::services::download_metadata::DownloadSettings> {
        use crate::services::download_metadata::DownloadSettings;
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT downloadfoldercover, downloadepisodecover, downloadmetadatasidecar,
                           downloadmetadataformat, downloadmetadatasubfolder
                    FROM "AppSettings"
                    LIMIT 1
                "#)
                .fetch_optional(pool)
                .await?;

                Ok(match row {
                    Some(row) => DownloadSettings {
                        folder_cover: row.try_get::<Option<bool>, _>("downloadfoldercover")?.unwrap_or(false),
                        episode_cover: row.try_get::<Option<bool>, _>("downloadepisodecover")?.unwrap_or(false),
                        metadata_sidecar: row.try_get::<Option<bool>, _>("downloadmetadatasidecar")?.unwrap_or(false),
                        metadata_format: row.try_get::<Option<String>, _>("downloadmetadataformat")?.unwrap_or_else(|| "both".to_string()),
                        metadata_subfolder: row.try_get::<Option<bool>, _>("downloadmetadatasubfolder")?.unwrap_or(true),
                    },
                    None => DownloadSettings::disabled(),
                })
            },
        })
    }

    // Update the admin download-metadata settings (#451/#533/#658).
    pub async fn set_download_settings(
        &self,
        settings: &crate::services::download_metadata::DownloadSettings,
    ) -> AppResult<()> {
        // Normalize the format to a known value so the UI can't persist junk.
        let format = match settings.metadata_format.as_str() {
            "json" | "xml" | "ffmetadata" | "both" => settings.metadata_format.as_str(),
            _ => "both",
        };
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"
                    UPDATE "AppSettings"
                    SET downloadfoldercover = $1,
                        downloadepisodecover = $2,
                        downloadmetadatasidecar = $3,
                        downloadmetadataformat = $4,
                        downloadmetadatasubfolder = $5
                "#)
                .bind(settings.folder_cover)
                .bind(settings.episode_cover)
                .bind(settings.metadata_sidecar)
                .bind(format)
                .bind(settings.metadata_subfolder)
                .execute(pool)
                .await?;
            },
        });
        Ok(())
    }

    // Save email settings - matches Python save_email_settings function exactly
    pub async fn save_email_settings(&self, email_settings: &crate::handlers::settings::EmailSettings) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                let auth_required = email_settings.auth_required != 0;
                q::query(
                    r#"UPDATE "EmailSettings" SET 
                       server_name = $1, server_port = $2, from_email = $3, 
                       send_mode = $4, encryption = $5, auth_required = $6, 
                       username = $7, password = $8 
                       WHERE emailsettingsid = 1"#
                )
                .bind(&email_settings.server_name)
                .bind(email_settings.server_port)
                .bind(&email_settings.from_email)
                .bind(&email_settings.send_mode)
                .bind(&email_settings.encryption)
                .bind(auth_required)
                .bind(&email_settings.email_username)
                .bind(&email_settings.email_password)
                .execute(pool)
                .await?;
            },
        });
        Ok(())
    }

    // Get email settings - matches Python get_email_settings function exactly
    pub async fn get_email_settings(&self) -> AppResult<Option<crate::handlers::settings::EmailSettingsResponse>> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(
                    r#"SELECT emailsettingsid, server_name, server_port, from_email, 
                       send_mode, encryption, auth_required, username, password 
                       FROM "EmailSettings""#
                )
                .fetch_optional(pool)
                .await?;

                if let Some(row) = row {
                    let auth_required: bool = row.try_get("auth_required")?;
                    Ok(Some(crate::handlers::settings::EmailSettingsResponse {
                        emailsettingsid: row.try_get("emailsettingsid")?,
                        server_name: row.try_get("server_name")?,
                        server_port: row.try_get("server_port")?,
                        from_email: row.try_get("from_email")?,
                        send_mode: row.try_get("send_mode")?,
                        encryption: row.try_get("encryption")?,
                        auth_required: if auth_required { 1 } else { 0 },
                        username: row.try_get("username")?,
                        password: row.try_get("password")?,
                    }))
                } else {
                    Ok(None)
                }
            },
        })
    }
}
