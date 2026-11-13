use crate::components::app_drawer::App_drawer;
use crate::components::audio_player_bar::AudioPlayerBar;
use crate::components::context::AppState;
use crate::components::gen_components::{empty_message, Search_nav, UseScrollToTop};
use crate::components::loading::Loading;
use crate::pages::podcast_layout::PodcastItem;
use crate::requests::discover_req::{
    call_get_categories, call_get_recommendations, call_get_trending, PodcastCategory,
    RecommendedPodcast,
};
use crate::requests::search_pods::UnifiedPodcast;
use i18nrs::yew::use_translation;
use wasm_bindgen_futures::spawn_local;
use yew::prelude::*;
use yewdux::prelude::*;

// A single responsive grid of PodcastItem cards (reuses the shared search-result card, which
// already handles the click-to-preview + one-click subscribe/unsubscribe flow).
fn podcast_grid(podcasts: &[UnifiedPodcast]) -> Html {
    html! {
        <div class="podcast-flex-container" style="display: flex; flex-wrap: wrap; gap: 16px; padding: 0 12px 24px; width: 100%;">
            { for podcasts.iter().map(|p| html! {
                <div style="width: calc(25% - 16px); min-width: 220px; flex-grow: 1; margin-bottom: 16px;">
                    <PodcastItem podcast={p.clone()} />
                </div>
            }) }
        </div>
    }
}

// Group recommendations by their explanation ("Because you listen to X"), preserving the
// score-sorted order so the strongest reason leads.
fn group_by_reason(recs: &[RecommendedPodcast]) -> Vec<(String, Vec<UnifiedPodcast>)> {
    let mut order: Vec<String> = Vec::new();
    let mut groups: std::collections::HashMap<String, Vec<UnifiedPodcast>> =
        std::collections::HashMap::new();
    for r in recs {
        if !groups.contains_key(&r.reason) {
            order.push(r.reason.clone());
        }
        groups.entry(r.reason.clone()).or_default().push(r.to_unified());
    }
    order
        .into_iter()
        .map(|reason| {
            let items = groups.remove(&reason).unwrap_or_default();
            (reason, items)
        })
        .collect()
}

#[function_component(Discover)]
pub fn discover() -> Html {
    let (i18n, _) = use_translation();
    let (post_state, _post_dispatch) = use_store::<AppState>();

    let loading = use_state(|| true);
    // Podcast discovery.
    let recommendations = use_state(Vec::<RecommendedPodcast>::new);
    let categories = use_state(Vec::<PodcastCategory>::new);
    let trending = use_state(Vec::<UnifiedPodcast>::new);
    let selected_category = use_state(|| None::<String>);
    let trending_loading = use_state(|| false);

    let api_key = post_state
        .auth_details
        .as_ref()
        .and_then(|ud| ud.api_key.clone());
    let server_name = post_state
        .auth_details
        .as_ref()
        .map(|ud| ud.server_name.clone());

    // Initial parallel load: recommendations + categories + global trending.
    {
        let api_key = api_key.clone();
        let server_name = server_name.clone();
        let loading = loading.clone();
        let recommendations = recommendations.clone();
        let categories = categories.clone();
        let trending = trending.clone();

        use_effect_with((), move |_| {
            if let (Some(server), Some(key)) = (server_name, api_key) {
                spawn_local(async move {
                    let (recs, cats, trend) = futures::join!(
                        call_get_recommendations(&server, &key, false),
                        call_get_categories(&server, &key),
                        call_get_trending(&server, &key, None, 24),
                    );
                    if let Ok(v) = recs {
                        recommendations.set(v);
                    }
                    if let Ok(mut v) = cats {
                        v.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
                        categories.set(v);
                    }
                    if let Ok(v) = trend {
                        trending.set(v);
                    }
                    loading.set(false);
                });
            } else {
                loading.set(false);
            }
            || ()
        });
    }

    // Clicking a category chip refetches trending for that category (None = All/global).
    let on_category_click = {
        let api_key = api_key.clone();
        let server_name = server_name.clone();
        let trending = trending.clone();
        let selected_category = selected_category.clone();
        let trending_loading = trending_loading.clone();
        Callback::from(move |cat: Option<String>| {
            selected_category.set(cat.clone());
            if let (Some(server), Some(key)) = (server_name.clone(), api_key.clone()) {
                let trending = trending.clone();
                let trending_loading = trending_loading.clone();
                trending_loading.set(true);
                spawn_local(async move {
                    let res =
                        call_get_trending(&server, &key, cat.as_deref(), 24).await;
                    if let Ok(v) = res {
                        trending.set(v);
                    }
                    trending_loading.set(false);
                });
            }
        })
    };

    // Pre-capture translation strings.
    let i18n_title = i18n.t("discover.title").to_string();
    let i18n_for_you = i18n.t("discover.for_you").to_string();
    let i18n_for_you_empty = i18n.t("discover.for_you_empty").to_string();
    let i18n_trending = i18n.t("discover.trending").to_string();
    let i18n_all_categories = i18n.t("discover.all_categories").to_string();
    let i18n_empty_title = i18n.t("discover.empty_title").to_string();
    let i18n_empty_message = i18n.t("discover.empty_message").to_string();

    let recommendation_groups = group_by_reason(&recommendations);

    // Precompute the "All" category chip's state + handler (html! child slots can't hold
    // `let` statements, so these must live outside the markup).
    let trending_all_active = selected_category.is_none();
    let on_all_click = {
        let on_category_click = on_category_click.clone();
        Callback::from(move |_: MouseEvent| on_category_click.emit(None))
    };

    html! {
        <>
        <div class="main-container">
            <Search_nav />
            <UseScrollToTop />
            {
                if *loading {
                    html! { <Loading/> }
                } else {
                    html! {
                        <div class="p-4">
                            <h1 class="text-2xl item_container-text font-bold text-center mb-6">{ &i18n_title }</h1>

                            // --- For You (personalized recommendations) ---
                            {
                                if recommendation_groups.is_empty() {
                                    html! {
                                        <div class="mb-8">
                                            <h2 class="item_container-text text-xl font-semibold mb-4">{ &i18n_for_you }</h2>
                                            <p class="item_container-text opacity-70">{ &i18n_for_you_empty }</p>
                                        </div>
                                    }
                                } else {
                                    html! {
                                        <div class="mb-8">
                                            <h2 class="item_container-text text-xl font-semibold mb-4">{ &i18n_for_you }</h2>
                                            { for recommendation_groups.iter().map(|(reason, items)| html! {
                                                <div class="mb-6">
                                                    <h3 class="item_container-text text-lg font-medium mb-3 opacity-90">{ reason }</h3>
                                                    { podcast_grid(items) }
                                                </div>
                                            }) }
                                        </div>
                                    }
                                }
                            }

                            // --- Trending, filterable by category ---
                            <div class="mb-8">
                                <h2 class="item_container-text text-xl font-semibold mb-4">{ &i18n_trending }</h2>
                                <div class="flex flex-wrap gap-2 mb-4">
                                    <button class={classes!("sp-chip", trending_all_active.then_some("is-active"))} onclick={on_all_click.clone()}>
                                        { &i18n_all_categories }
                                    </button>
                                    { for categories.iter().map(|cat| {
                                        let name = cat.name.clone();
                                        let is_active = selected_category.as_deref() == Some(name.as_str());
                                        let on_click = {
                                            let on_category_click = on_category_click.clone();
                                            let name = name.clone();
                                            Callback::from(move |_: MouseEvent| on_category_click.emit(Some(name.clone())))
                                        };
                                        html! {
                                            <button class={classes!("sp-chip", is_active.then_some("is-active"))} onclick={on_click}>
                                                { &cat.name }
                                            </button>
                                        }
                                    }) }
                                </div>
                                {
                                    if *trending_loading {
                                        html! { <Loading/> }
                                    } else if trending.is_empty() {
                                        empty_message(&i18n_empty_title, &i18n_empty_message)
                                    } else {
                                        podcast_grid(&trending)
                                    }
                                }
                            </div>

                        </div>
                    }
                }
            }
            <AudioPlayerBar />
        </div>
        <App_drawer />
        </>
    }
}
