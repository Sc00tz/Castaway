//! OIDC login: the callback's token exchange and provider discovery, against a fixture IdP.

use crate::harness::*;

/// The role a fixture provider restricts logins to (see [`add_provider_with`]).
const LOGIN_ROLE: &str = "podcasters";

/// Registers a typical provider: a verified email, a stable `sub`, and logins restricted to
/// [`LOGIN_ROLE`], which is what lets a first login create an account. Returns its client_id.
async fn add_provider(app: &TestApp, email: &str) -> String {
    let userinfo = json!({
        "sub": format!("sub-{email}"),
        "email": email,
        "email_verified": true,
        "name": "Oidc User",
        "groups": [LOGIN_ROLE],
    });
    add_provider_with(app, userinfo, true).await
}

/// Registers a provider whose token and userinfo endpoints are fixtures, the userinfo endpoint
/// answering with `userinfo`. With `role_restricted`, logins require [`LOGIN_ROLE`] in the
/// `groups` claim. Returns its client_id.
async fn add_provider_with(app: &TestApp, userinfo: serde_json::Value, role_restricted: bool) -> String {
    let admin = app.admin().await;
    let fx = app.fixtures();
    let token_url = fx.serve(
        "idp/token",
        Fixture::new("application/json", r#"{"access_token":"fixture-token","token_type":"Bearer"}"#),
    );
    let userinfo_url = fx.serve("idp/userinfo", Fixture::new("application/json", userinfo.to_string()));
    let client_id = format!("pinepods-{}", fx.namespace);
    let mut provider = json!({
        "provider_name": "Fixture IdP",
        "client_id": client_id,
        "client_secret": "fixture-secret",
        "authorization_url": fx.url("idp/authorize"),
        "token_url": token_url,
        "user_info_url": userinfo_url,
        "button_text": "Fixture",
        "scope": "openid email profile",
        "button_color": "#000000",
        "button_text_color": "#ffffff",
    });
    if role_restricted {
        provider["roles_claim"] = json!("groups");
        provider["user_role"] = json!(LOGIN_ROLE);
    }
    app.post("/api/data/add_oidc_provider").key(admin).json(&provider).send().await.assert_ok();
    client_id
}

/// Completes an SSO login against the fixture provider; returns where the browser is sent.
async fn sso_login(app: &TestApp, client_id: &str) -> String {
    let state = format!("state-{}", app.fixtures().namespace);
    app.post("/api/auth/store_state")
        .json(&json!({ "state": state, "client_id": client_id, "origin_url": "https://pods.example.test" }))
        .send()
        .await
        .assert_ok();
    let resp = app
        .get("/api/auth/callback")
        .header("host", "pods.example.test")
        .header("x-forwarded-proto", "https")
        .query("code", "fixture-code")
        .query("state", &state)
        .send()
        .await;
    resp.headers.get("location").and_then(|v| v.to_str().ok()).unwrap_or_default().to_string()
}

#[tokio::test(flavor = "multi_thread")]
async fn an_unverified_email_cannot_sign_in_as_an_existing_account() {
    let app = TestApp::new().await;
    let admin = app.admin().await;
    // Someone registered the admin's address at the provider, which didn't verify it.
    let userinfo = json!({
        "sub": "intruder",
        "email": admin.email,
        "email_verified": false,
        "groups": [LOGIN_ROLE],
    });
    let client_id = add_provider_with(&app, userinfo, true).await;
    let location = sso_login(&app, &client_id).await;
    assert!(location.contains("error=email_not_verified"), "{location}");
    assert!(!location.contains("api_key="), "{location}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_verified_email_signs_in_to_the_matching_account() {
    let app = TestApp::new().await;
    let user = app.user("ssolinked").await;
    let client_id = add_provider(&app, &user.email).await;
    let location = sso_login(&app, &client_id).await;
    assert!(location.contains(&format!("api_key={}", user.api_key)), "the existing account's key: {location}");
}

#[tokio::test(flavor = "multi_thread")]
async fn without_a_role_restriction_sso_creates_no_accounts() {
    let app = TestApp::new().await;
    // Any account at a public provider (think GitHub) could sign in here.
    let userinfo = json!({ "sub": "stranger", "email": "stranger@example.test", "email_verified": true });
    let client_id = add_provider_with(&app, userinfo, false).await;
    let location = sso_login(&app, &client_id).await;
    assert!(location.contains("error=registration_disabled"), "{location}");
    assert!(!location.contains("api_key="), "{location}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_first_sso_login_creates_an_account_when_logins_are_restricted() {
    let app = TestApp::new().await;
    let client_id = add_provider(&app, "oidc-new@example.test").await;
    let location = sso_login(&app, &client_id).await;
    assert!(location.contains("api_key="), "{location}");
    // The second login finds the same account by its subject.
    let again = sso_login(&app, &client_id).await;
    let key = |loc: &str| loc.split("api_key=").nth(1).and_then(|s| s.split('&').next()).map(String::from);
    assert_eq!(key(&location), key(&again), "{location} vs {again}");
}

fn form_field(body: &[u8], key: &str) -> Option<String> {
    url::form_urlencoded::parse(body).find(|(k, _)| k == key).map(|(_, v)| v.into_owned())
}

#[tokio::test(flavor = "multi_thread")]
async fn token_exchange_repeats_the_clients_redirect_uri() {
    let app = TestApp::new().await;
    let client_id = add_provider(&app, "oidc-port@example.test").await;

    // Served on a non-default port behind a proxy whose Host header drops it.
    let redirect_uri = "https://pods.example.test:12345/api/auth/callback";
    let state = format!("state-{}", app.fixtures().namespace);
    app.post("/api/auth/store_state")
        .json(&json!({
            "state": state,
            "client_id": client_id,
            "origin_url": "https://pods.example.test:12345",
            "redirect_uri": redirect_uri,
        }))
        .send()
        .await
        .assert_ok();

    let resp = app
        .get("/api/auth/callback")
        .header("host", "pods.example.test")
        .header("x-forwarded-proto", "https")
        .query("code", "fixture-code")
        .query("state", &state)
        .send()
        .await;
    let location = resp.headers.get("location").and_then(|v| v.to_str().ok()).unwrap_or_default().to_string();
    assert!(location.contains("api_key="), "{} {location} {}", resp.status, resp.text());
    assert!(location.starts_with("https://pods.example.test:12345/oauth/callback"), "{location}");
    assert!(location.ends_with(&format!("&state={state}")), "the client checks the login is its own: {location}");

    let hits = app.fixtures().hits("idp/token");
    assert_eq!(hits.len(), 1);
    assert_eq!(form_field(&hits[0].body, "redirect_uri").as_deref(), Some(redirect_uri));
}

#[tokio::test(flavor = "multi_thread")]
async fn token_exchange_falls_back_to_request_host_for_old_clients() {
    let app = TestApp::new().await;
    let client_id = add_provider(&app, "oidc-legacy@example.test").await;
    let state = format!("state-{}", app.fixtures().namespace);
    app.post("/api/auth/store_state")
        .json(&json!({ "state": state, "client_id": client_id, "origin_url": "https://pods.example.test" }))
        .send()
        .await
        .assert_ok();

    app.get("/api/auth/callback")
        .header("host", "pods.example.test")
        .header("x-forwarded-proto", "https")
        .query("code", "fixture-code")
        .query("state", &state)
        .send()
        .await;

    let hits = app.fixtures().hits("idp/token");
    assert_eq!(hits.len(), 1);
    assert_eq!(
        form_field(&hits[0].body, "redirect_uri").as_deref(),
        Some("https://pods.example.test/api/auth/callback")
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn the_api_key_never_goes_to_a_foreign_origin() {
    let app = TestApp::new().await;
    let client_id = add_provider(&app, "oidc-victim@example.test").await;
    let state = format!("state-{}", app.fixtures().namespace);
    // Anyone can store a state; this one names an origin that isn't the server.
    app.post("/api/auth/store_state")
        .json(&json!({ "state": state, "client_id": client_id, "origin_url": "https://attacker.example.test" }))
        .send()
        .await
        .assert_ok();

    let resp = app
        .get("/api/auth/callback")
        .header("host", "pods.example.test")
        .header("x-forwarded-proto", "https")
        .query("code", "fixture-code")
        .query("state", &state)
        .send()
        .await;
    let location = resp.headers.get("location").and_then(|v| v.to_str().ok()).unwrap_or_default().to_string();
    assert!(location.starts_with("https://pods.example.test/oauth/callback?"), "{} {location}", resp.status);
    assert!(!location.contains("attacker"), "{location}");
}

#[tokio::test(flavor = "multi_thread")]
async fn store_state_rejects_foreign_redirect_uris() {
    let app = TestApp::new().await;
    for bad in ["https://evil.example.test/collect", "pinepods://auth/callback", "not a url"] {
        app.post("/api/auth/store_state")
            .json(&json!({ "state": "s", "client_id": "c", "redirect_uri": bad }))
            .send()
            .await
            .assert_status(400);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn discovery_fills_endpoints_for_admins() {
    let app = TestApp::new().await;
    let admin = app.admin().await;
    let fx = app.fixtures();
    let issuer = fx.url("issuer");
    fx.serve(
        "issuer/.well-known/openid-configuration",
        Fixture::new(
            "application/json",
            json!({
                "issuer": issuer,
                "authorization_endpoint": format!("{issuer}/authorize"),
                "token_endpoint": format!("{issuer}/token"),
                "userinfo_endpoint": format!("{issuer}/userinfo"),
                "jwks_uri": format!("{issuer}/jwks"),
                "scopes_supported": ["openid", "email", "profile"],
            })
            .to_string(),
        ),
    );

    // Both the issuer and the full document URL work.
    for url in [issuer.clone(), format!("{issuer}/.well-known/openid-configuration")] {
        let doc = app.post("/api/data/oidc_discovery").key(admin).json(&json!({ "url": url })).send().await.ok_json();
        assert_eq!(doc["token_endpoint"], format!("{issuer}/token"));
        assert_eq!(doc["userinfo_endpoint"], format!("{issuer}/userinfo"));
    }

    let missing = app.post("/api/data/oidc_discovery").key(admin).json(&json!({ "url": fx.url("nowhere") })).send().await;
    missing.assert_status(400);
    assert!(missing.text().contains("404"), "{}", missing.text());
}
