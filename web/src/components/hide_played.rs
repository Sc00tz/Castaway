//! The "Hide played" toggle shared by the web app's episode lists. Each list remembers its own
//! choice in this browser.

use std::collections::HashSet;

use i18nrs::yew::use_translation;
use yew::prelude::*;

use crate::components::gen_funcs::{get_filter_preference, set_filter_preference};

fn pref_key(list: &str) -> String {
    format!("{list}_hide_played")
}

/// Whether `list` hides played episodes, and a callback that flips (and remembers) it.
#[hook]
pub fn use_hide_played(list: &'static str) -> (bool, Callback<MouseEvent>) {
    let on = use_state(move || get_filter_preference(&pref_key(list)).as_deref() == Some("1"));
    let toggle = {
        let on = on.clone();
        Callback::from(move |_: MouseEvent| {
            let next = !*on;
            set_filter_preference(&pref_key(list), if next { "1" } else { "0" });
            on.set(next);
        })
    };
    (*on, toggle)
}

/// Whether an episode is played. Pages add the played episodes they load to the session's set,
/// and marking an episode played or unplayed updates it, so the set is current where the
/// episode's own flag may not be.
pub fn is_played(episode_id: i32, session_completed: &HashSet<i32>) -> bool {
    session_completed.contains(&episode_id)
}

#[derive(Properties, PartialEq)]
pub struct HidePlayedChipProps {
    pub active: bool,
    pub onclick: Callback<MouseEvent>,
}

#[function_component(HidePlayedChip)]
pub fn hide_played_chip(props: &HidePlayedChipProps) -> Html {
    let (i18n, _) = use_translation();
    html! {
        <button
            type="button"
            class={classes!("sp-chip", props.active.then_some("is-active"))}
            aria-pressed={props.active.to_string()}
            onclick={props.onclick.clone()}
        >
            <i class={if props.active { "ph-fill ph-eye-slash" } else { "ph ph-eye-slash" }}></i>
            <span>{ i18n.t("hide_played.label") }</span>
        </button>
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen_test::wasm_bindgen_test;

    #[wasm_bindgen_test]
    fn played_comes_from_the_session_set() {
        let session: HashSet<i32> = [3].into_iter().collect();
        assert!(is_played(3, &session));
        assert!(!is_played(4, &session));
    }
}
