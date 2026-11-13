use crate::harness::*;

#[tokio::test(flavor = "multi_thread")]
async fn boots_and_logs_in() {
    let app = TestApp::new().await;
    let check = app.get("/api/castaway_check").send().await.ok_json();
    assert_eq!(check["castaway_instance"], true, "{check}");
    let admin = app.admin().await;
    let body = app.get("/api/data/verify_key").key(admin).send().await.ok_json();
    assert_eq!(body["status"], "success", "{body}");
    let alice = app.user("alice").await;
    assert_ne!(alice.id, admin.id);
}

/// Apps from before 0.10.2 use the old check and version addresses.
#[tokio::test(flavor = "multi_thread")]
async fn older_apps_still_find_the_server() {
    let app = TestApp::new().await;
    let check = app.get("/api/pinepods_check").send().await.ok_json();
    assert_eq!(check["pinepods_instance"], true, "{check}");
    let alice = app.user("alice").await;
    let old = app.get("/api/data/get_pinepods_version").key(&alice).send().await.ok_json();
    let new = app.get("/api/data/get_castaway_version").key(&alice).send().await.ok_json();
    assert_eq!(old, new);
    app.get("/api/data/get_pinepods_version").send().await.assert_status(401);
}
