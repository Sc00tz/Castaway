//! Sanitizing HTML that comes from feeds.
//!
//! Podcast and episode descriptions are HTML written by whoever controls the feed. They are
//! cleaned once, here, when a feed is parsed, so every client (web, mobile, desktop, anything
//! reading the API) gets HTML that can't run scripts. The web app sanitizes again when it
//! renders, for rows stored before this existed.

use std::collections::HashMap;
use std::sync::LazyLock;

static FEED_HTML: LazyLock<ammonia::Builder<'static>> = LazyLock::new(|| {
    let mut builder = ammonia::Builder::default();
    // Ammonia's defaults already drop scripts, event handlers, styles, forms, iframes and
    // `javascript:` URLs, and add rel="noopener noreferrer" to links. Links also open in a new
    // tab, matching what the web app does.
    builder.add_tag_attributes("a", &["target"]);
    builder.set_tag_attribute_values(HashMap::from([("a", HashMap::from([("target", "_blank")]))]));
    builder
});

/// Clean feed-supplied HTML for storage and display.
///
/// Text without a `<` holds no markup, so it's returned unchanged rather than entity-escaped
/// (which would show up as `&amp;` in clients that display descriptions as plain text).
pub fn sanitize_feed_html(html: &str) -> String {
    if !html.contains('<') {
        return html.to_string();
    }
    FEED_HTML.clean(html).to_string()
}

#[cfg(test)]
mod tests {
    use super::sanitize_feed_html;

    #[test]
    fn removes_everything_that_can_run_script() {
        let attacks = [
            r#"<img src=x onerror="alert(1)">"#,
            r#"<script>alert(1)</script>"#,
            r#"<a href="javascript:alert(1)">x</a>"#,
            r#"<svg onload="alert(1)"></svg>"#,
            r#"<iframe src="https://evil.test"></iframe>"#,
            r#"<p style="background:url(javascript:alert(1))" onclick="alert(1)">x</p>"#,
            r#"<form action="https://evil.test"><input name=k></form>"#,
        ];
        for html in attacks {
            let clean = sanitize_feed_html(html).to_lowercase();
            for bad in ["<script", "onerror", "onload", "onclick", "javascript:", "<iframe", "<svg", "<form", "style="] {
                assert!(!clean.contains(bad), "{:?} survived in {:?} (from {:?})", bad, clean, html);
            }
        }
    }

    #[test]
    fn keeps_show_notes_formatting() {
        let clean = sanitize_feed_html(r#"<p>Show <b>notes</b> <a href="https://a.test/">link</a></p><ul><li>one</li></ul>"#);
        assert!(clean.contains("<b>notes</b>"));
        assert!(clean.contains("<ul><li>one</li></ul>"));
        assert!(clean.contains(r#"href="https://a.test/""#));
        assert!(clean.contains(r#"target="_blank""#));
        assert!(clean.contains("noopener"));
    }

    #[test]
    fn plain_text_passes_through_unescaped() {
        assert_eq!(sanitize_feed_html("Just text & more"), "Just text & more");
        assert_eq!(sanitize_feed_html("Q&amp;A already escaped"), "Q&amp;A already escaped");
    }
}
