//! People on podcasts and episodes: the shared people strip (podcast banner, mobile chips,
//! episode cards) and the follow button. Credits come from the feeds' own tags.

use std::rc::Rc;

use i18nrs::yew::use_translation;
use wasm_bindgen_futures::spawn_local;
use yew::prelude::*;
use yew_router::history::{BrowserHistory, History};
use yewdux::prelude::*;

use crate::components::context::{AppState, NotificationState};
use crate::requests::notify;
use crate::requests::people_req::{call_set_following, CreditedPerson};

/// Server name and API key of the signed-in user.
#[hook]
pub fn use_auth() -> Option<(String, String)> {
    let auth = use_selector(|state: &AppState| {
        state
            .auth_details
            .as_ref()
            .and_then(|a| a.api_key.clone().map(|key| (a.server_name.clone(), key)))
    });
    (*auth).clone()
}

pub fn proxied_image(server_name: &str, url: &str) -> String {
    format!(
        "{}/api/proxy/image?url={}",
        server_name,
        urlencoding::encode(url)
    )
}

pub fn person_path(person_id: i32) -> String {
    format!("/person/{}", person_id)
}

fn go_to_person(person_id: i32, on_open: Option<Callback<()>>) -> Callback<MouseEvent> {
    Callback::from(move |_: MouseEvent| {
        if let Some(on_open) = &on_open {
            on_open.emit(());
        }
        BrowserHistory::new().push(person_path(person_id))
    })
}

fn avatar(server_name: &str, person: &CreditedPerson, class: &'static str, placeholder: &'static str) -> Html {
    html! {
        <PersonAvatar
            src={person.img.as_deref().filter(|s| !s.is_empty()).map(|img| AttrValue::from(proxied_image(server_name, img)))}
            alt={person.name.clone()}
            {class}
            {placeholder}
        />
    }
}

#[derive(Properties, PartialEq, Clone)]
pub struct PersonAvatarProps {
    pub src: Option<AttrValue>,
    #[prop_or_default]
    pub alt: AttrValue,
    pub class: &'static str,
    /// Extra class for the icon placeholder shown when there's no image or it fails to load.
    pub placeholder: &'static str,
}

/// A person's picture, or a user icon when there's none or it doesn't load.
#[function_component(PersonAvatar)]
pub fn person_avatar(props: &PersonAvatarProps) -> Html {
    let failed = use_state(|| false);
    {
        let failed = failed.clone();
        use_effect_with(props.src.clone(), move |_| {
            failed.set(false);
            || ()
        });
    }
    match &props.src {
        Some(src) if !*failed => {
            let failed = failed.clone();
            html! {
                <img src={src.clone()} alt={props.alt.clone()} class={props.class} loading="lazy"
                     onerror={Callback::from(move |_: Event| failed.set(true))} />
            }
        }
        _ => html! { <div class={classes!(props.class, props.placeholder)}><i class="ph ph-user"></i></div> },
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum PeopleLayout {
    /// Overlapping avatars plus "Hosted by A & B" (desktop podcast banner).
    Banner,
    /// A labelled, horizontally scrolling row of chips (mobile pages, guests).
    Chips,
    /// A grid of cards with follow buttons (episode People tab).
    Cards,
}

#[derive(Properties, PartialEq, Clone)]
pub struct PeopleStripProps {
    pub people: Rc<Vec<CreditedPerson>>,
    pub layout: PeopleLayout,
    #[prop_or_default]
    pub label: AttrValue,
    /// Text shown when nobody is credited; without it, an empty strip renders nothing.
    #[prop_or_default]
    pub empty_text: AttrValue,
    /// Wrapper class, so pages keep their own spacing.
    #[prop_or_default]
    pub class: Classes,
    /// Runs before opening a person page (the player collapses itself).
    #[prop_or_default]
    pub on_open: Option<Callback<()>>,
}

#[function_component(PeopleStrip)]
pub fn people_strip(props: &PeopleStripProps) -> Html {
    let server_name = use_auth().map(|(s, _)| s).unwrap_or_default();
    let people = &props.people;

    if people.is_empty() {
        if props.empty_text.is_empty() {
            return html! {};
        }
        return html! {
            <div class={classes!("pp-empty", props.class.clone())}>
                { if props.label.is_empty() { html! {} } else { html! { <span class="pp-label">{ &props.label }</span> } } }
                <div class="pp-empty-row">
                    <span class="pp-empty-text">{ &props.empty_text }</span>
                </div>
            </div>
        };
    }

    match props.layout {
        PeopleLayout::Banner => {
            let shown: Vec<CreditedPerson> = people.iter().take(6).cloned().collect();
            let more = people.len().saturating_sub(shown.len());
            html! {
                <div class={classes!("pd-banner-hosts", props.class.clone())}>
                    <div class="pd-host-stack">
                        { for shown.iter().map(|p| html! {
                            <div class="pd-host-avatar-wrap" title={p.name.clone()} onclick={go_to_person(p.id, props.on_open.clone())}>
                                { avatar(&server_name, p, "pd-host-avatar", "pd-host-avatar-ph") }
                            </div>
                        }) }
                    </div>
                    <div class="pd-host-label">
                        <span class="pd-host-by">{ &props.label }</span>
                        <span class="pd-host-names">
                            { for shown.iter().enumerate().map(|(i, p)| {
                                let sep = if i == 0 { "" } else if i + 1 == shown.len() && more == 0 { " & " } else { ", " };
                                html! {
                                    <>
                                        { sep }
                                        <a class="pp-name-link" onclick={go_to_person(p.id, props.on_open.clone())}>{ &p.name }</a>
                                        
                                    </>
                                }
                            }) }
                            { if more > 0 { html! { <span class="pp-more">{ format!(" +{}", more) }</span> } } else { html! {} } }
                        </span>
                    </div>
                </div>
            }
        }
        PeopleLayout::Chips => html! {
            <div class={classes!("pp-chips-section", props.class.clone())}>
                <div class="pp-head">
                    { if props.label.is_empty() { html! {} } else { html! { <span class="pp-label">{ &props.label }</span> } } }
                </div>
                <div class="ep-mobile-hosts-scroll">
                    { for people.iter().map(|p| html! {
                        <div class="ep-mobile-host-chip" onclick={go_to_person(p.id, props.on_open.clone())} title={p.name.clone()}>
                            <div class="pp-chip-avatar">
                                { avatar(&server_name, p, "ep-mobile-host-avatar", "ep-mobile-host-placeholder") }
                                
                            </div>
                            <span class="ep-mobile-host-name">{ &p.name }</span>
                            <span class="ep-mobile-host-role">{ &p.role }</span>
                        </div>
                    }) }
                </div>
            </div>
        },
        PeopleLayout::Cards => html! {
            <div class={classes!(props.class.clone())}>
                <div class="ep-people">
                    { for people.iter().map(|p| {
                        let roles = p.roles.join(", ");
                        let roles = if roles.is_empty() { p.role.clone() } else { roles };
                        html! {
                            <div class="ep-person" onclick={go_to_person(p.id, props.on_open.clone())} title={p.name.clone()}>
                                { avatar(&server_name, p, "ep-person-avatar", "ep-person-avatar-ph") }
                                <div class="ep-person-body">
                                    <div class="ep-person-name">{ &p.name }</div>
                                    <span class="ep-person-role">{ roles }</span>
                                </div>
                                <FollowButton person_id={p.id} followed={p.followed} compact={true} />
                            </div>
                        }
                    }) }
                </div>
            </div>
        },
    }
}

#[derive(Properties, PartialEq, Clone)]
pub struct FollowButtonProps {
    pub person_id: i32,
    pub followed: bool,
    /// Icon-only.
    #[prop_or_default]
    pub compact: bool,
    #[prop_or_default]
    pub on_change: Option<Callback<bool>>,
}

/// Follow / unfollow toggle. Optimistic; reverts with a toast if the server says no.
#[function_component(FollowButton)]
pub fn follow_button(props: &FollowButtonProps) -> Html {
    let (i18n, _) = use_translation();
    let auth = use_auth();
    let following = use_state(|| props.followed);
    let busy = use_state(|| false);
    {
        let following = following.clone();
        use_effect_with((props.person_id, props.followed), move |(_, followed)| {
            following.set(*followed);
            || ()
        });
    }

    let label_follow = i18n.t("people.follow").to_string();
    let label_following = i18n.t("people.following").to_string();
    let label_unfollow = i18n.t("people.unfollow").to_string();
    let failed = i18n.t("people.follow_failed").to_string();

    let onclick = {
        let following = following.clone();
        let busy = busy.clone();
        let person_id = props.person_id;
        let on_change = props.on_change.clone();
        Callback::from(move |e: MouseEvent| {
            e.stop_propagation();
            let Some((server, key)) = auth.clone() else { return };
            if *busy {
                return;
            }
            let target = !*following;
            following.set(target);
            busy.set(true);
            let following = following.clone();
            let busy = busy.clone();
            let on_change = on_change.clone();
            let failed = failed.clone();
            spawn_local(async move {
                match call_set_following(&server, &key, person_id, target).await {
                    Ok(()) => {
                        if let Some(cb) = on_change {
                            cb.emit(target);
                        }
                    }
                    Err(e) => {
                        following.set(!target);
                        notify::toast_error(&Dispatch::<NotificationState>::global(), format!("{}: {}", failed, e));
                    }
                }
                busy.set(false);
            });
        })
    };

    let is_following = *following;
    let (icon, text) = if is_following {
        ("ph-user-check", label_following.clone())
    } else {
        ("ph-user-plus", label_follow.clone())
    };
    let title = if is_following { label_unfollow } else { label_follow };
    html! {
        <button
            type="button"
            class={classes!("pp-follow", is_following.then_some("is-following"), props.compact.then_some("is-compact"))}
            title={title.clone()}
            aria-label={title}
            aria-pressed={is_following.to_string()}
            disabled={*busy}
            {onclick}
        >
            <i class={classes!("ph", icon)}></i>
            { if props.compact { html! {} } else { html! { <span>{ text }</span> } } }
        </button>
    }
}
