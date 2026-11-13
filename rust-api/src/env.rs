//! Castaway's own environment settings, named `CASTAWAY_*`. A setup carried over from PinePods
//! may still use the `PINEPODS_*` names, so those are read too, with a note to rename them.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

const PREFIX: &str = "CASTAWAY_";
const OLD_PREFIX: &str = "PINEPODS_";

/// The value of `CASTAWAY_<name>`, else the old `PINEPODS_<name>`. Blank values count as unset.
pub fn var(name: &str) -> Option<String> {
    let read = |n: &str| std::env::var(n).ok().filter(|v| !v.trim().is_empty());
    let new = format!("{PREFIX}{name}");
    if let Some(v) = read(&new) {
        return Some(v);
    }
    let old = format!("{OLD_PREFIX}{name}");
    let v = read(&old)?;
    static NOTED: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    if NOTED.get_or_init(Default::default).lock().map(|mut s| s.insert(old.clone())).unwrap_or(false) {
        tracing::warn!("{old} is the old name for {new}; rename it, the old name may stop working");
    }
    Some(v)
}

/// The full name of a setting, for messages.
pub fn name(name: &str) -> String {
    format!("{PREFIX}{name}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_new_name_wins_and_the_old_one_still_works() {
        std::env::set_var("PINEPODS_ENVTEST_A", "old");
        assert_eq!(var("ENVTEST_A").as_deref(), Some("old"));
        std::env::set_var("CASTAWAY_ENVTEST_A", "new");
        assert_eq!(var("ENVTEST_A").as_deref(), Some("new"));
        std::env::set_var("CASTAWAY_ENVTEST_B", "  ");
        assert_eq!(var("ENVTEST_B"), None);
    }
}
