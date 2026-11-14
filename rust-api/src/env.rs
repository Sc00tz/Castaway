//! Castaway's own environment settings, all named `CASTAWAY_*`.

const PREFIX: &str = "CASTAWAY_";

/// The value of `CASTAWAY_<name>`. Blank values count as unset.
pub fn var(name: &str) -> Option<String> {
    std::env::var(format!("{PREFIX}{name}")).ok().filter(|v| !v.trim().is_empty())
}

/// The full name of a setting, for messages.
pub fn name(name: &str) -> String {
    format!("{PREFIX}{name}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_are_read_under_their_castaway_names() {
        std::env::set_var("CASTAWAY_ENVTEST_A", "set");
        assert_eq!(var("ENVTEST_A").as_deref(), Some("set"));
        std::env::set_var("CASTAWAY_ENVTEST_B", "  ");
        assert_eq!(var("ENVTEST_B"), None);
        assert_eq!(name("PORT"), "CASTAWAY_PORT");
    }
}
