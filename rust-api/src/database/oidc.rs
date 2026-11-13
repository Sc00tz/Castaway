//! OIDC providers and OIDC-created users.

use super::*;

#[derive(Debug, Clone)]
pub struct PublicOidcProvider {
    pub provider_id: i32,
    pub provider_name: String,
    pub client_id: String,
    pub authorization_url: String,
    pub scope: String,
    pub button_color: String,
    pub button_text: String,
    pub button_text_color: String,
    pub icon_svg: Option<String>,
}

impl DatabasePool {
    // Get public OIDC providers - matches Python get_public_oidc_providers function
    pub async fn get_public_oidc_providers(&self) -> AppResult<Vec<PublicOidcProvider>> {
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(
                    r#"SELECT
                        providerid,
                        providername,
                        clientid,
                        authorizationurl,
                        scope,
                        buttoncolor,
                        buttontext,
                        buttontextcolor,
                        iconsvg
                    FROM "OIDCProviders"
                    WHERE enabled = true"#
                )
                .fetch_all(pool)
                .await?;
                
                let mut providers = Vec::new();
                for row in rows {
                    providers.push(PublicOidcProvider {
                        provider_id: row.try_get("providerid")?,
                        provider_name: row.try_get("providername")?,
                        client_id: row.try_get("clientid")?,
                        authorization_url: row.try_get("authorizationurl")?,
                        scope: row.try_get("scope")?,
                        button_color: row.try_get("buttoncolor")?,
                        button_text: row.try_get("buttontext")?,
                        button_text_color: row.try_get("buttontextcolor")?,
                        icon_svg: row.try_get("iconsvg").ok(),
                    });
                }
                Ok(providers)
            },
        })
    }

    // Add OIDC provider - matches Python add_oidc_provider function exactly
    pub async fn add_oidc_provider(&self, provider_name: &str, client_id: &str, client_secret: &str, authorization_url: &str, token_url: &str, user_info_url: &str, button_text: &str, scope: &str, button_color: &str, button_text_color: &str, icon_svg: &str, name_claim: &str, email_claim: &str, username_claim: &str, roles_claim: &str, user_role: &str, admin_role: &str, initialized_from_env: bool) -> AppResult<i32> {
        debug!("Adding OIDC provider: {}", provider_name);
        
        let provider_id = dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    INSERT INTO "OIDCProviders" (
                        providername, clientid, clientsecret, authorizationurl,
                        tokenurl, userinfourl, buttontext, scope,
                        buttoncolor, buttontextcolor, iconsvg, nameclaim, emailclaim,
                        usernameclaim, rolesclaim, userrole, adminrole, initializedFromEnv
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
                    RETURNING providerid
                "#)
                    .bind(provider_name)
                    .bind(client_id)
                    .bind(client_secret)
                    .bind(authorization_url)
                    .bind(token_url)
                    .bind(user_info_url)
                    .bind(button_text)
                    .bind(scope)
                    .bind(button_color)
                    .bind(button_text_color)
                    .bind(icon_svg)
                    .bind(name_claim)
                    .bind(email_claim)
                    .bind(username_claim)
                    .bind(roles_claim)
                    .bind(user_role)
                    .bind(admin_role)
                    .bind(initialized_from_env)
                    .fetch_one(pool)
                    .await?;
                
                row.try_get("providerid")?
            },
        });
        
        debug!("Successfully added OIDC provider with ID: {}", provider_id);
        Ok(provider_id)
    }

    // List OIDC providers - matches Python list_oidc_providers function exactly
    pub async fn list_oidc_providers(&self) -> AppResult<Vec<serde_json::Value>> {
        info!("Listing all OIDC providers");
        
        let providers = dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(r#"
                    SELECT providerid, providername, clientid, authorizationurl,
                           tokenurl, userinfourl, buttontext, scope, buttoncolor,
                           buttontextcolor, iconsvg, nameclaim, emailclaim, usernameclaim,
                           rolesclaim, userrole, adminrole, enabled, created, modified, initializedfromenv
                    FROM "OIDCProviders" 
                    ORDER BY providername
                "#)
                    .fetch_all(pool)
                    .await?;
                
                let mut providers = Vec::new();
                for row in rows {
                    let provider = serde_json::json!({
                        "provider_id": row.try_get::<i32, _>("providerid")?,
                        "provider_name": row.try_get::<String, _>("providername")?,
                        "client_id": row.try_get::<String, _>("clientid")?,
                        "authorization_url": row.try_get::<String, _>("authorizationurl")?,
                        "token_url": row.try_get::<String, _>("tokenurl")?,
                        "user_info_url": row.try_get::<String, _>("userinfourl")?,
                        "button_text": row.try_get::<String, _>("buttontext")?,
                        "scope": row.try_get::<String, _>("scope")?,
                        "button_color": row.try_get::<String, _>("buttoncolor")?,
                        "button_text_color": row.try_get::<String, _>("buttontextcolor")?,
                        "icon_svg": row.try_get::<Option<String>, _>("iconsvg")?,
                        "name_claim": row.try_get::<Option<String>, _>("nameclaim")?,
                        "email_claim": row.try_get::<Option<String>, _>("emailclaim")?,
                        "username_claim": row.try_get::<Option<String>, _>("usernameclaim")?,
                        "roles_claim": row.try_get::<Option<String>, _>("rolesclaim")?,
                        "user_role": row.try_get::<Option<String>, _>("userrole")?,
                        "admin_role": row.try_get::<Option<String>, _>("adminrole")?,
                        "enabled": row.try_get::<bool, _>("enabled")?,
                        "created": row.try_get::<Option<chrono::NaiveDateTime>, _>("created")?,
                        "modified": row.try_get::<Option<chrono::NaiveDateTime>, _>("modified")?,
                        "initialized_from_env": row.try_get::<bool, _>("initializedfromenv").unwrap_or(false)
                    });
                    providers.push(provider);
                }
                providers
            },
        });
        
        debug!("Found {} OIDC providers", providers.len());
        Ok(providers)
    }

    // Remove OIDC provider - matches Python remove_oidc_provider function exactly
    pub async fn remove_oidc_provider(&self, provider_id: i32) -> AppResult<bool> {
        info!("Removing OIDC provider with ID: {}", provider_id);
        
        let rows_affected = dialect_match!(self, {
            pg(pool) => {
                let result = q::query(r#"DELETE FROM "OIDCProviders" WHERE ProviderID = $1"#)
                    .bind(provider_id)
                    .execute(pool)
                    .await?;
                
                result.rows_affected()
            },
        });
        
        let success = rows_affected > 0;
        if success {
            info!("Successfully removed OIDC provider with ID: {}", provider_id);
        } else {
            debug!("No OIDC provider found with ID: {}", provider_id);
        }
        Ok(success)
    }

    // Initialize OIDC provider from environment variables on container startup
    pub async fn init_oidc_from_env(&self, oidc_config: &OIDCConfig) -> AppResult<()> {
        if !oidc_config.is_configured() {
            debug!("OIDC environment variables not configured, skipping initialization");
            return Ok(());
        }

        let provider_name = oidc_config.provider_name.as_ref().unwrap();
        let client_id = oidc_config.client_id.as_ref().unwrap();
        
        // Check if provider already exists
        let existing = self.get_oidc_provider_by_client_id(client_id).await?;
        if existing.is_some() {
            debug!("OIDC provider with client_id '{}' already exists, skipping initialization", client_id);
            return Ok(());
        }

        info!("Initializing OIDC provider '{}' from environment variables", provider_name);

        // Explicit endpoint variables win; discovery fills whichever are unset.
        let (mut authorization_url, mut token_url, mut user_info_url) = (
            oidc_config.authorization_url.clone(),
            oidc_config.token_url.clone(),
            oidc_config.user_info_url.clone(),
        );
        if authorization_url.is_none() || token_url.is_none() || user_info_url.is_none() {
            let discovery_url = oidc_config.discovery_url.as_deref().unwrap_or_default();
            let discovered = crate::services::oidc::discover(discovery_url)
                .await
                .map_err(|e| AppError::internal(&format!("OIDC discovery failed: {}", e)))?;
            authorization_url.get_or_insert(discovered.authorization_endpoint);
            token_url.get_or_insert(discovered.token_endpoint);
            user_info_url.get_or_insert(discovered.userinfo_endpoint);
        }

        // Role claims default to empty (no role check), matching providers added in the UI.
        let provider_id = self.add_oidc_provider(
            provider_name,
            client_id,
            oidc_config.client_secret.as_ref().unwrap(),
            authorization_url.as_deref().unwrap_or_default(),
            token_url.as_deref().unwrap_or_default(),
            user_info_url.as_deref().unwrap_or_default(),
            oidc_config.button_text.as_ref().unwrap(),
            oidc_config.scope.as_deref().unwrap_or("openid email profile"),
            oidc_config.button_color.as_deref().unwrap_or("#000000"),
            oidc_config.button_text_color.as_deref().unwrap_or("#FFFFFF"),
            oidc_config.icon_svg.as_deref().unwrap_or(""),
            oidc_config.name_claim.as_deref().unwrap_or("name"),
            oidc_config.email_claim.as_deref().unwrap_or("email"),
            oidc_config.username_claim.as_deref().unwrap_or("preferred_username"),
            oidc_config.roles_claim.as_deref().unwrap_or(""),
            oidc_config.user_role.as_deref().unwrap_or(""),
            oidc_config.admin_role.as_deref().unwrap_or(""),
            true, // initialized_from_env = true
        ).await?;

        info!("Successfully initialized OIDC provider '{}' with ID: {}", provider_name, provider_id);
        Ok(())
    }

    // Check if OIDC provider was initialized from environment variables
    pub async fn is_oidc_provider_env_initialized(&self, provider_id: i32) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let result = q::query(r#"
                    SELECT initializedfromenv FROM "OIDCProviders" WHERE providerid = $1
                "#)
                    .bind(provider_id)
                    .fetch_optional(pool)
                    .await?;
                
                Ok(result.map(|row| row.try_get::<bool, _>("initializedfromenv").unwrap_or(false)).unwrap_or(false))
            },
        })
    }

    // Update OIDC provider - updates an existing provider with new values
    // If client_secret is None, the existing secret will be preserved
    pub async fn update_oidc_provider(&self, provider_id: i32, provider_name: &str, client_id: &str, client_secret: Option<&str>, authorization_url: &str, token_url: &str, user_info_url: &str, button_text: &str, scope: &str, button_color: &str, button_text_color: &str, icon_svg: &str, name_claim: &str, email_claim: &str, username_claim: &str, roles_claim: &str, user_role: &str, admin_role: &str) -> AppResult<bool> {
        info!("Updating OIDC provider with ID: {}", provider_id);

        let rows_affected = dialect_match!(self, {
            pg(pool) => {
                // Build query dynamically based on whether client_secret is provided
                if let Some(secret) = client_secret {
                    let result = q::query(r#"
                        UPDATE "OIDCProviders" SET
                            providername = $2, clientid = $3, clientsecret = $4,
                            authorizationurl = $5, tokenurl = $6, userinfourl = $7,
                            buttontext = $8, scope = $9, buttoncolor = $10,
                            buttontextcolor = $11, iconsvg = $12, nameclaim = $13,
                            emailclaim = $14, usernameclaim = $15, rolesclaim = $16,
                            userrole = $17, adminrole = $18, modified = CURRENT_TIMESTAMP
                        WHERE providerid = $1
                    "#)
                        .bind(provider_id)
                        .bind(provider_name)
                        .bind(client_id)
                        .bind(secret)
                        .bind(authorization_url)
                        .bind(token_url)
                        .bind(user_info_url)
                        .bind(button_text)
                        .bind(scope)
                        .bind(button_color)
                        .bind(button_text_color)
                        .bind(icon_svg)
                        .bind(name_claim)
                        .bind(email_claim)
                        .bind(username_claim)
                        .bind(roles_claim)
                        .bind(user_role)
                        .bind(admin_role)
                        .execute(pool)
                        .await?;
                    result.rows_affected()
                } else {
                    // Don't update client_secret if not provided
                    let result = q::query(r#"
                        UPDATE "OIDCProviders" SET
                            providername = $2, clientid = $3,
                            authorizationurl = $4, tokenurl = $5, userinfourl = $6,
                            buttontext = $7, scope = $8, buttoncolor = $9,
                            buttontextcolor = $10, iconsvg = $11, nameclaim = $12,
                            emailclaim = $13, usernameclaim = $14, rolesclaim = $15,
                            userrole = $16, adminrole = $17, modified = CURRENT_TIMESTAMP
                        WHERE providerid = $1
                    "#)
                        .bind(provider_id)
                        .bind(provider_name)
                        .bind(client_id)
                        .bind(authorization_url)
                        .bind(token_url)
                        .bind(user_info_url)
                        .bind(button_text)
                        .bind(scope)
                        .bind(button_color)
                        .bind(button_text_color)
                        .bind(icon_svg)
                        .bind(name_claim)
                        .bind(email_claim)
                        .bind(username_claim)
                        .bind(roles_claim)
                        .bind(user_role)
                        .bind(admin_role)
                        .execute(pool)
                        .await?;
                    result.rows_affected()
                }
            },
        });
        
        let success = rows_affected > 0;
        if success {
            debug!("Successfully updated OIDC provider with ID: {}", provider_id);
        } else {
            debug!("No OIDC provider found with ID: {}", provider_id);
        }
        Ok(success)
    }

    // OIDC Provider Management - matches Python OIDC functions

    // Get OIDC provider by client ID - for callback processing
    pub async fn get_oidc_provider_by_client_id(&self, client_id: &str) -> AppResult<Option<serde_json::Value>> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT providerid, providername, clientid, clientsecret, authorizationurl, 
                           tokenurl, userinfourl, scope, buttoncolor, buttontext, buttontextcolor, 
                           iconsvg, enabled, nameclaim, emailclaim, usernameclaim, rolesclaim, 
                           userrole, adminrole
                    FROM "OIDCProviders" 
                    WHERE clientid = $1 AND enabled = true
                "#)
                    .bind(client_id)
                    .fetch_optional(pool)
                    .await?;

                if let Some(row) = row {
                    Ok(Some(serde_json::json!({
                        "provider_id": row.try_get::<i32, _>("providerid")?,
                        "provider_name": row.try_get::<String, _>("providername")?,
                        "client_id": row.try_get::<String, _>("clientid")?,
                        "client_secret": row.try_get::<String, _>("clientsecret")?,
                        "authorization_url": row.try_get::<String, _>("authorizationurl")?,
                        "token_url": row.try_get::<String, _>("tokenurl")?,
                        "userinfo_url": row.try_get::<String, _>("userinfourl")?,
                        "scope": row.try_get::<String, _>("scope")?,
                        "button_color": row.try_get::<String, _>("buttoncolor")?,
                        "button_text": row.try_get::<String, _>("buttontext")?,
                        "button_text_color": row.try_get::<String, _>("buttontextcolor")?,
                        "icon_svg": row.try_get::<Option<String>, _>("iconsvg")?,
                        "enabled": row.try_get::<bool, _>("enabled")?,
                        "name_claim": row.try_get::<Option<String>, _>("nameclaim")?,
                        "email_claim": row.try_get::<Option<String>, _>("emailclaim")?,
                        "username_claim": row.try_get::<Option<String>, _>("usernameclaim")?,
                        "roles_claim": row.try_get::<Option<String>, _>("rolesclaim")?,
                        "user_role": row.try_get::<Option<String>, _>("userrole")?,
                        "admin_role": row.try_get::<Option<String>, _>("adminrole")?
                    })))
                } else {
                    Ok(None)
                }
            },
        })
    }

    // Get OIDC provider - matches Python get_oidc_provider function EXACTLY
    pub async fn get_oidc_provider(&self, client_id: &str) -> AppResult<Option<(i32, String, String, String, String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>)>> {
        dialect_match!(self, {
            pg(pool) => {
                let result = q::query(r#"
                    SELECT providerid, clientid, clientsecret, tokenurl, userinfourl, nameclaim, emailclaim, usernameclaim, rolesclaim, userrole, adminrole
                    FROM "OIDCProviders"
                    WHERE clientid = $1 AND enabled = true
                "#)
                    .bind(client_id)
                    .fetch_optional(pool)
                    .await?;

                if let Some(row) = result {
                    Ok(Some((
                        row.try_get("providerid")?,
                        row.try_get("clientid")?,
                        row.try_get("clientsecret")?,
                        row.try_get("tokenurl")?,
                        row.try_get("userinfourl")?,
                        row.try_get("nameclaim")?,
                        row.try_get("emailclaim")?,
                        row.try_get("usernameclaim")?,
                        row.try_get("rolesclaim")?,
                        row.try_get("userrole")?,
                        row.try_get("adminrole")?,
                    )))
                } else {
                    Ok(None)
                }
            },
        })
    }

    // Create OIDC user - matches Python create_oidc_user function EXACTLY
    pub async fn create_oidc_user(&self, email: &str, fullname: &str, username: &str) -> AppResult<i32> {
        use base64::{Engine as _, engine::general_purpose::STANDARD};

        // Create salt exactly like Python version
        let salt_bytes: [u8; 16] = rand::random();
        let salt = STANDARD.encode(salt_bytes);
        let hashed_password = format!("$argon2id$v=19$m=65536,t=3,p=4${}${}_OIDC_ACCOUNT_NO_PASSWORD", 
                                    salt, "X".repeat(43));

        dialect_match!(self, {
            pg(pool) => {
                let result = q::query(r#"
                    INSERT INTO "Users" (fullname, username, email, hashed_pw, isadmin)
                    VALUES ($1, $2, $3, $4, false)
                    RETURNING userid
                "#)
                    .bind(fullname)
                    .bind(username)
                    .bind(email)
                    .bind(&hashed_password)
                    .fetch_one(pool)
                    .await?;

                let user_id: i32 = result.try_get("userid")?;

                // Add default user settings
                q::query(r#"INSERT INTO "UserSettings" (userid, theme) VALUES ($1, $2)"#)
                    .bind(user_id)
                    .bind("Nordic")
                    .execute(pool)
                    .await?;

                // Add default user stats
                q::query(r#"INSERT INTO "UserStats" (userid) VALUES ($1)"#)
                    .bind(user_id)
                    .execute(pool)
                    .await?;

                Ok(user_id)
            },
        })
    }

    /// The account linked to `subject` (the provider's permanent user id, its `sub` claim) at
    /// `provider_id`, with its username. This, not the email address, is what identifies a
    /// returning SSO user: emails can change hands or be unverified, `sub` can't.
    pub async fn get_user_by_oidc_subject(&self, provider_id: i32, subject: &str) -> AppResult<Option<(i32, Option<String>)>> {
        Ok(dialect_match!(self, {
            pg(pool) => {
                q::query(r#"SELECT userid, username FROM "Users" WHERE oidc_provider_id = $1 AND oidc_subject = $2 ORDER BY userid LIMIT 1"#)
                    .bind(provider_id)
                    .bind(subject)
                    .fetch_optional(pool)
                    .await?
                    .map(|row| -> AppResult<_> { Ok((row.try_get("userid")?, row.try_get("username")?)) })
                    .transpose()?
            },
        }))
    }

    /// The SSO identity (provider id, subject) an account is linked to, if any.
    pub async fn get_user_oidc_identity(&self, user_id: i32) -> AppResult<(Option<i32>, Option<String>)> {
        Ok(dialect_match!(self, {
            pg(pool) => {
                match q::query(r#"SELECT oidc_provider_id, oidc_subject FROM "Users" WHERE userid = $1"#)
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?
                {
                    Some(row) => (row.try_get("oidc_provider_id")?, row.try_get("oidc_subject")?),
                    None => (None, None),
                }
            },
        }))
    }

    /// Link an account to an SSO identity, so later logins find it by `sub` instead of email.
    pub async fn set_user_oidc_identity(&self, user_id: i32, provider_id: i32, subject: &str) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"UPDATE "Users" SET oidc_provider_id = $1, oidc_subject = $2 WHERE userid = $3"#)
                    .bind(provider_id)
                    .bind(subject)
                    .bind(user_id)
                    .execute(pool)
                    .await?;
            },
        });
        Ok(())
    }
}
