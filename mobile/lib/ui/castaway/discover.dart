// lib/ui/castaway/discover.dart
//
// Discover: "For You" (shows like the ones you follow, grouped by why) and Trending, filterable
// by category. The server answers from Podcast Index when it has a key, otherwise from Apple's
// charts, so this works without a key. Matches the web app's Discover page.

import 'package:flutter/material.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/entities/discover.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/ui/widgets/podcast_result_card.dart';
import 'package:castaway_mobile/ui/widgets/soft_ui.dart';
import 'package:provider/provider.dart';
import 'package:sliver_tools/sliver_tools.dart';

/// Suggestions shown per reason, so one reason can't fill the page.
const int _perReason = 4;

class CastawayDiscover extends StatefulWidget {
  /// Tests pass their own client; the app uses the signed-in server.
  final CastawayService? service;

  const CastawayDiscover({super.key, this.service});

  @override
  State<CastawayDiscover> createState() => _CastawayDiscoverState();
}

class _CastawayDiscoverState extends State<CastawayDiscover> {
  late final CastawayService _service = widget.service ?? CastawayService();
  int? _userId;

  bool _loading = true;
  String? _error;
  List<(String, List<UnifiedCastawayPodcast>)> _forYou = [];
  List<DiscoverCategory> _categories = [];
  String? _category;
  bool _trendingLoading = false;
  List<UnifiedCastawayPodcast> _trending = [];
  Set<String> _following = {};

  @override
  void initState() {
    super.initState();
    CastawayService.libraryChanged.addListener(_loadFollowing);
    _load();
  }

  @override
  void dispose() {
    CastawayService.libraryChanged.removeListener(_loadFollowing);
    super.dispose();
  }

  bool _connect() {
    if (widget.service != null) return true;
    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
    if (settings.castawayServer == null || settings.castawayApiKey == null || settings.castawayUserId == null) {
      return false;
    }
    _service.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
    _userId = settings.castawayUserId;
    return true;
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!_connect()) {
      setState(() {
        _loading = false;
        _error = L.of(context)!.not_connected_please_login;
      });
      return;
    }
    _userId ??= await _service.getUserIdFromApiKey();

    // Suggestions and categories are extras: the page still shows trending without them.
    final results = await Future.wait<Object>([
      _attempt(() => _service.getRecommendations(refresh: refresh), orElse: (_) => <Recommendation>[]),
      _attempt(() => _service.getDiscoverCategories(), orElse: (_) => <DiscoverCategory>[]),
      _attempt(() => _service.getTrending(category: _category), orElse: (e) => e),
    ]);
    await _loadFollowing();
    if (!mounted) return;
    setState(() {
      _forYou = groupByReason(results[0] as List<Recommendation>);
      _categories = results[1] as List<DiscoverCategory>;
      final trending = results[2];
      if (trending is List<UnifiedCastawayPodcast>) {
        _trending = trending;
      } else {
        _error = L.of(context)!.discover_unavailable(trending.toString().replaceFirst('Exception: ', ''));
      }
      _loading = false;
    });
  }

  /// The result of [call], or what [orElse] makes of its error.
  static Future<Object> _attempt(Future<Object> Function() call, {required Object Function(Object error) orElse}) async {
    try {
      return await call();
    } catch (e) {
      return orElse(e);
    }
  }

  Future<void> _loadFollowing() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final podcasts = await _service.getUserPodcasts(userId);
      if (mounted) setState(() => _following = {for (final p in podcasts) p.url});
    } catch (_) {
      // The follow buttons just show "Follow" until the next load.
    }
  }

  Future<void> _selectCategory(String? category) async {
    if (category == _category) return;
    setState(() {
      _category = category;
      _trendingLoading = true;
    });
    try {
      final trending = await _service.getTrending(category: category);
      if (mounted && _category == category) setState(() => _trending = trending);
    } catch (e) {
      if (mounted) _snack(L.of(context)!.discover_unavailable(e.toString().replaceFirst('Exception: ', '')));
    } finally {
      if (mounted && _category == category) setState(() => _trendingLoading = false);
    }
  }

  Future<void> _toggle(UnifiedCastawayPodcast podcast) async {
    final userId = _userId;
    if (userId == null) return;
    final l = L.of(context)!;
    final following = _following.contains(podcast.url);
    try {
      final ok = following
          ? await _service.removePodcast(podcast.title, podcast.url, userId)
          : await _service.addPodcast(podcast, userId);
      if (!mounted) return;
      if (ok) {
        _setFollowing(podcast, !following);
        _snack(following ? l.podcast_removed : l.podcast_added);
      } else {
        _snack(following ? l.failed_to_remove_podcast : l.failed_to_add_podcast);
      }
    } catch (e) {
      if (mounted) _snack(l.error_with_detail(e.toString()));
    }
  }

  void _setFollowing(UnifiedCastawayPodcast podcast, bool following) {
    setState(() => following ? _following.add(podcast.url) : _following.remove(podcast.url));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Widget _card(UnifiedCastawayPodcast podcast) => PodcastResultCard(
        podcast: podcast,
        isAdded: _following.contains(podcast.url),
        onToggle: () => _toggle(podcast),
        onFollowChanged: (following) => _setFollowing(podcast, following),
      );

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final theme = Theme.of(context);
    final header = SliverToBoxAdapter(
      child: SoftSectionHeader(
        title: l.nav_discover,
        trailing: [
          IconButton(
            tooltip: l.refresh,
            icon: const Icon(PhosphorIconsRegular.arrowClockwise),
            onPressed: _loading ? null : () => _load(refresh: true),
          ),
        ],
      ),
    );

    if (_loading) {
      return MultiSliver(children: [
        header,
        const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
      ]);
    }
    if (_error != null && _trending.isEmpty) {
      return MultiSliver(children: [
        header,
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SoftEmptyState(
              icon: PhosphorIconsRegular.compass,
              title: _error!,
              action: TextButton(onPressed: _load, child: Text(l.retry)),
            ),
          ),
        ),
      ]);
    }

    return MultiSliver(children: [
      header,
      // --- For You ---
      SliverToBoxAdapter(child: _sectionTitle(l.discover_for_you, theme)),
      if (_forYou.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l.discover_for_you_empty, style: TextStyle(color: theme.hintColor)),
          ),
        )
      else
        for (final (reason, podcasts) in _forYou) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(reason, style: theme.textTheme.titleSmall?.copyWith(color: theme.hintColor)),
            ),
          ),
          SliverList.list(children: [for (final p in podcasts.take(_perReason)) _card(p)]),
        ],
      // --- Trending ---
      SliverToBoxAdapter(child: _sectionTitle(l.discover_trending, theme)),
      if (_categories.isNotEmpty) SliverToBoxAdapter(child: _categoryChips()),
      if (_trendingLoading)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        )
      else if (_trending.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(l.discover_nothing_trending, textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
          ),
        )
      else
        SliverList.list(children: [for (final p in _trending) _card(p)]),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ]);
  }

  Widget _sectionTitle(String text, ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _categoryChips() {
    final l = L.of(context)!;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterPill(label: l.discover_all_categories, selected: _category == null, onTap: () => _selectCategory(null)),
          ),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterPill(label: c.name, selected: _category == c.name, onTap: () => _selectCategory(c.name)),
            ),
        ],
      ),
    );
  }
}
