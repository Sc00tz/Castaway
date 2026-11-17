//! The image proxy (`/api/proxy/image`) fetches addresses the web page asks for, so it goes
//! through the same guard as every other outside fetch: the address, what its host resolves
//! to, and every redirect must be public.

use crate::harness::*;

fn png() -> Vec<u8> {
    // A 1x1 PNG.
    vec![
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6,
        0, 0, 0, 0x1F, 0x15, 0xC4, 0x89, 0, 0, 0, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0, 1, 0, 0, 5, 0, 1, 0x0D,
        0x0A, 0x2D, 0xB4, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]
}

fn proxied(url: &str) -> String {
    format!("/api/proxy/image?url={}", urlencoding::encode(url))
}

#[tokio::test(flavor = "multi_thread")]
async fn an_image_is_fetched_and_served() {
    let app = TestApp::new().await;
    let url = app.fixtures().serve("art/cover.png", Fixture::new("image/png", png()));
    let resp = app.get(&proxied(&url)).send().await;
    resp.assert_status(200);
    assert_eq!(resp.body, png());
}

#[tokio::test(flavor = "multi_thread")]
async fn private_and_cloud_metadata_addresses_are_refused() {
    let app = TestApp::new().await;
    for url in ["http://169.254.169.254/latest/meta-data/", "http://10.0.0.1/cover.png", "http://192.168.1.1/cover.png", "http://[fd00::1]/cover.png"] {
        app.get(&proxied(url)).send().await.assert_status(403);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_redirect_to_an_internal_address_is_refused() {
    let app = TestApp::new().await;
    let url = app.fixtures().serve(
        "art/redirect.png",
        Fixture::new("text/plain", "").status(302).header("location", "http://169.254.169.254/latest/meta-data/"),
    );
    let resp = app.get(&proxied(&url)).send().await;
    assert_ne!(resp.status.as_u16(), 200, "the redirect must not be followed");
}
