// Admin: the Podcast Index API key Castaway searches with. Apple Podcasts search needs no key;
// Podcast Index search, person search, trending and categories need one (free from
// api.podcastindex.org). The secret is checked with Podcast Index, stored encrypted, and never
// shown again.

use crate::components::context::{AppState, NotificationState};
use crate::requests::setting_reqs::{call_get_podcast_index, call_set_podcast_index, PodcastIndexStatus};
use i18nrs::yew::use_translation;
use wasm_bindgen_futures::spawn_local;
use web_sys::HtmlInputElement;
use yew::prelude::*;
use yewdux::prelude::*;

fn notify(error: Option<String>, info: Option<String>) {
    Dispatch::<NotificationState>::global().reduce_mut(|s| {
        if error.is_some() {
            s.error_message = error;
        }
        if info.is_some() {
            s.info_message = info;
        }
    });
}

#[function_component(PodcastIndexSection)]
pub fn podcast_index_section() -> Html {
    let (i18n, _) = use_translation();
    let (state, _) = use_store::<AppState>();
    let auth = state
        .auth_details
        .as_ref()
        .and_then(|a| a.api_key.clone().map(|k| (a.server_name.clone(), k)));
    let status = use_state(|| None::<PodcastIndexStatus>);
    let key = use_state(String::new);
    let secret = use_state(String::new);
    let saving = use_state(|| false);

    {
        let (status, key, auth) = (status.clone(), key.clone(), auth.clone());
        use_effect_with(auth.clone(), move |_| {
            if let Some((server, api_key)) = auth {
                spawn_local(async move {
                    match call_get_podcast_index(&server, &api_key).await {
                        Ok(s) => {
                            key.set(s.api_key.clone().unwrap_or_default());
                            status.set(Some(s));
                        }
                        Err(e) => notify(Some(e.to_string()), None),
                    }
                });
            }
            || ()
        });
    }

    let save = {
        let (auth, status, key, secret, saving) = (auth.clone(), status.clone(), key.clone(), secret.clone(), saving.clone());
        let saved_msg = i18n.t("podcast_index.saved").to_string();
        let removed_msg = i18n.t("podcast_index.removed").to_string();
        move |remove: bool| {
            let Some((server, api_key)) = auth.clone() else { return };
            let (k, s) = if remove { (String::new(), String::new()) } else { ((*key).clone(), (*secret).clone()) };
            let (status, key, secret, saving) = (status.clone(), key.clone(), secret.clone(), saving.clone());
            let done_msg = if remove { removed_msg.clone() } else { saved_msg.clone() };
            saving.set(true);
            spawn_local(async move {
                match call_set_podcast_index(&server, &api_key, &k, &s).await {
                    Ok(st) => {
                        key.set(st.api_key.clone().unwrap_or_default());
                        secret.set(String::new());
                        status.set(Some(st));
                        notify(None, Some(done_msg));
                    }
                    Err(e) => notify(Some(e.to_string()), None),
                }
                saving.set(false);
            });
        }
    };
    let on_save = {
        let save = save.clone();
        Callback::from(move |_: MouseEvent| save(false))
    };
    let on_remove = Callback::from(move |_: MouseEvent| save(true));

    let Some(st) = (*status).clone() else {
        return html! { <div class="settings-row"><div class="settings-row-desc"><i class="ph ph-spinner animate-spin"></i></div></div> };
    };
    let on_key = {
        let key = key.clone();
        Callback::from(move |e: InputEvent| key.set(e.target_unchecked_into::<HtmlInputElement>().value()))
    };
    let on_secret = {
        let secret = secret.clone();
        Callback::from(move |e: InputEvent| secret.set(e.target_unchecked_into::<HtmlInputElement>().value()))
    };

    html! {
        <>
            <div class="settings-row">
                <div class="settings-row-label">
                    <div>{ i18n.t("podcast_index.status_label") }</div>
                    <div class="settings-row-desc">
                        { if st.configured { i18n.t("podcast_index.configured") } else { i18n.t("podcast_index.not_configured") } }
                    </div>
                </div>
            </div>
            <div class="settings-row" style="flex-wrap: wrap;">
                <div class="settings-row-label">
                    <div>{ i18n.t("podcast_index.key_label") }</div>
                    <div class="settings-row-desc">{ i18n.t("podcast_index.key_help") }</div>
                </div>
                <div class="settings-row-control" style="flex: 1 1 260px; min-width: 0; flex-direction: column; align-items: stretch; gap: 8px;">
                    <input class="input" type="text" autocomplete="off" disabled={*saving}
                        placeholder={i18n.t("podcast_index.key_placeholder")}
                        value={(*key).clone()} oninput={on_key} />
                    <input class="input" type="password" autocomplete="new-password" disabled={*saving}
                        placeholder={if st.configured { i18n.t("podcast_index.secret_saved_placeholder") } else { i18n.t("podcast_index.secret_placeholder") }}
                        value={(*secret).clone()} oninput={on_secret} />
                    <div style="display: flex; gap: 8px; justify-content: flex-end;">
                        { if st.configured {
                            html! { <button class="btn btn-ghost" disabled={*saving} onclick={on_remove}>{ i18n.t("podcast_index.remove") }</button> }
                        } else { html! {} } }
                        <button class="btn btn-secondary" disabled={*saving || key.trim().is_empty() || secret.trim().is_empty()} onclick={on_save}>
                            { if *saving { html! { <i class="ph ph-spinner animate-spin"></i> } } else { html! {} } }
                            <span>{ i18n.t("podcast_index.save") }</span>
                        </button>
                    </div>
                </div>
            </div>
        </>
    }
}
