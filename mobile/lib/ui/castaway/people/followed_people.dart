// lib/ui/castaway/people/followed_people.dart
//
// The People tab: find anyone credited in this server's feeds, everyone the
// user follows, and one combined list of their latest episodes across every
// show.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:castaway_mobile/entities/people.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/services/global_services.dart';
import 'package:castaway_mobile/ui/castaway/episode_details.dart';
import 'package:castaway_mobile/ui/castaway/people/people_widgets.dart';
import 'package:castaway_mobile/ui/utils/player_utils.dart';
import 'package:castaway_mobile/ui/widgets/castaway_episode_card.dart';
import 'package:castaway_mobile/ui/widgets/platform_progress_indicator.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/l10n/L.dart';

/// Episodes fetched per person, and the most shown in the combined list.
const int _perPerson = 20;
const int _feedLimit = 100;

/// The People tab. A single sliver, like the other bottom-bar pages.
class CastawayPeople extends StatefulWidget {
  const CastawayPeople({super.key});

  @override
  State<CastawayPeople> createState() => _CastawayPeopleState();
}

class _CastawayPeopleState extends State<CastawayPeople> {
  List<PersonInfo>? _people;
  List<CastawayEpisode>? _feed;

  /// Shows outside the library, by name, so their episodes can open the show.
  final Map<String, PersonPodcast> _externalShows = {};
  String? _error;

  final _searchController = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  List<PersonHit>? _hits;
  bool _searching = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = signedInService(context);
    if (service == null) {
      setState(() => _error = L.of(context)!.not_connected_to_a_castaway_server);
      return;
    }
    try {
      final people = await service.getFollowedPeople();
      if (!mounted) return;
      setState(() {
        _people = people;
        _error = null;
      });

      final profiles = await Future.wait(people.map((p) async {
        try {
          return await service.getPersonProfile(p.id, limit: _perPerson);
        } catch (_) {
          return null;
        }
      }));
      final seen = <String>{};
      final episodes = <CastawayEpisode>[];
      for (final profile in profiles.whereType<PersonProfile>()) {
        for (final show in profile.podcasts.where((s) => !s.inLibrary)) {
          _externalShows[show.podcastName] = show;
        }
        for (final ep in [...profile.episodes, ...profile.externalEpisodes]) {
          // The same episode can credit several followed people.
          if (seen.add(ep.episodeUrl)) episodes.add(ep);
        }
      }
      episodes.sort((a, b) => b.episodePubDate.compareTo(a.episodePubDate));
      if (!mounted) return;
      setState(() => _feed = episodes.take(_feedLimit).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    if (query.length < 2) {
      _searchSeq++;
      setState(() {
        _hits = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final service = signedInService(context);
      if (service == null) return;
      final seq = ++_searchSeq;
      List<PersonHit> hits;
      try {
        hits = await service.searchPeople(query);
      } catch (_) {
        hits = [];
      }
      // Only the latest query's results are kept.
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
    FocusScope.of(context).unfocus();
  }

  /// Open a person page, then refresh: they may have been followed or
  /// unfollowed there.
  Future<void> _open(int personId, String name) async {
    await openPerson(context, personId, name: name);
    if (mounted) _load();
  }

  Future<void> _openHit(PersonHit hit) async {
    if (_opening) return;
    final id = hit.personId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.of(context)!.couldnt_open_name(hit.name))));
      return;
    }
    await _open(id, hit.name);
  }

  Future<void> _play(CastawayEpisode episode) async {
    final audio = GlobalServices.castawayAudioService;
    if (audio == null) return;
    try {
      await playCastawayEpisodeWithOptionalFullScreen(context, audio, episode, resume: episode.isStarted);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.of(context)!.failed_to_play_episode(e.toString()))));
    }
  }

  void _openEpisode(CastawayEpisode episode) {
    if (episode.episodeId > 0) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (context) => CastawayEpisodeDetails(initialEpisode: episode)),
      );
    } else if (_externalShows[episode.podcastName] case final show?) {
      openPersonPodcast(context, show);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searching = _hits != null || _searching;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _searchBar()),
        if (searching) ..._searchResults() else ..._followed(),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: L.of(context)!.find_hosts_and_guests,
          prefixIcon: const Icon(PhosphorIconsRegular.userFocus),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(icon: const Icon(PhosphorIconsRegular.x), tooltip: L.of(context)!.clear, onPressed: _clearSearch),
        ),
      ),
    );
  }

  List<Widget> _searchResults() {
    final theme = Theme.of(context);
    final hits = _hits;
    if (hits == null || (_searching && hits.isEmpty)) {
      return const [
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(32), child: Center(child: PlatformProgressIndicator())),
        ),
      ];
    }
    if (hits.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              L.of(context)!.nobody_found,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ];
    }
    return [
      if (_opening) const SliverToBoxAdapter(child: LinearProgressIndicator()),
      SliverList.builder(
        itemCount: hits.length,
        itemBuilder: (context, index) {
          final hit = hits[index];
          return ListTile(
            leading: PersonAvatar(url: hit.img, size: 44),
            title: Text(hit.name),
            trailing: hit.followed ? Icon(PhosphorIconsFill.checkCircle, color: theme.colorScheme.primary) : null,
            onTap: () => _openHit(hit),
          );
        },
      ),
    ];
  }

  List<Widget> _followed() {
    final theme = Theme.of(context);
    final people = _people;
    if (people == null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: _error == null
                  ? const PlatformProgressIndicator()
                  : Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: Text(L.of(context)!.retry)),
                      ],
                    ),
            ),
          ),
        ),
      ];
    }
    if (people.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(PhosphorIconsRegular.users, size: 64, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(L.of(context)!.not_following_anyone, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  L.of(context)!.not_following_anyone_body,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final feed = _feed;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            L.of(context)!.following_count(people.length),
            style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 96,
            mainAxisExtent: 116,
            crossAxisSpacing: 4,
          ),
          itemCount: people.length,
          itemBuilder: (context, index) {
            final person = people[index];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _open(person.id, person.name),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    PersonAvatar(url: person.img, size: 64),
                    const SizedBox(height: 6),
                    Text(
                      person.name,
                      style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(L.of(context)!.latest_episodes, style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold)),
        ),
      ),
      if (feed == null)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(32), child: Center(child: PlatformProgressIndicator())),
        )
      else if (feed.isEmpty)
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.all(32), child: Text(L.of(context)!.no_episodes_yet, textAlign: TextAlign.center)),
        )
      else
        SliverList.builder(
          itemCount: feed.length,
          itemBuilder: (context, index) {
            final episode = feed[index];
            return CastawayEpisodeCard(
              episode: episode,
              onTap: () => _openEpisode(episode),
              onPlayPressed: () => _play(episode),
            );
          },
        ),
    ];
  }
}
