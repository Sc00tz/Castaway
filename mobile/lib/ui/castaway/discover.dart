// lib/ui/castaway/discover.dart
//
// Discover: "For You" (shows like the ones you follow, grouped by why) and Trending, filterable
// by category. The server answers from Podcast Index when it has a key, otherwise from Apple's
// charts, so this works without a key. Matches the web app's Discover page.

import 'package:flutter/material.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:castaway_mobile/ui/castaway/search.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';
import 'package:castaway_mobile/ui/widgets/lazy_network_image.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/entities/discover.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
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

  void _openPodcast(UnifiedCastawayPodcast podcast) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => CastawayPodcastDetails(
          podcast: podcast,
          isFollowing: _following.contains(podcast.url),
          onFollowChanged: (following) => _setFollowing(podcast, following),
        ),
      ),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'castaway_search'),
        builder: (context) => const CastawaySearch(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final style = CastawayStyle.of(context);
    final header = MultiSliver(children: [
      SliverToBoxAdapter(
        child: TabHeader(
          title: l.nav_discover,
          actions: [
            IconButton(
              tooltip: l.refresh,
              icon: const Icon(PhosphorIconsRegular.arrowClockwise),
              onPressed: _loading ? null : () => _load(refresh: true),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: SearchBoxButton(
            key: const ValueKey('discover-search'),
            hint: l.search_for_podcasts_hint,
            onTap: _openSearch,
          ),
        ),
      ),
    ]);

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
      // --- For You: one row of artwork per reason ---
      SliverToBoxAdapter(child: _sectionTitle(l.discover_for_you, style)),
      if (_forYou.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l.discover_for_you_empty, style: TextStyle(color: style.muted)),
          ),
        )
      else
        for (final (reason, podcasts) in _forYou) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(reason, style: TextStyle(fontSize: 13, color: style.muted)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 172,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: podcasts.take(_perReason).length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final podcast = podcasts[index];
                  return _DiscoverTile(
                    podcast: podcast,
                    following: _following.contains(podcast.url),
                    onOpen: () => _openPodcast(podcast),
                    onToggle: () => _toggle(podcast),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      // --- Trending: numbered list, filterable by category ---
      SliverToBoxAdapter(child: _sectionTitle(l.discover_trending, style)),
      if (_categories.isNotEmpty) SliverToBoxAdapter(child: _categoryChips()),
      if (_trendingLoading)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        )
      else if (_trending.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(l.discover_nothing_trending, textAlign: TextAlign.center, style: TextStyle(color: style.muted)),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList.list(children: [
            for (final (i, p) in _trending.indexed)
              _TrendingRow(
                key: ValueKey('trending-${p.title}'),
                rank: i + 1,
                podcast: p,
                following: _following.contains(p.url),
                onOpen: () => _openPodcast(p),
                onToggle: () => _toggle(p),
              ),
          ]),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ]);
  }

  Widget _sectionTitle(String text, CastawayStyle style) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Semantics(
          header: true,
          child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: style.text)),
        ),
      );

  Widget _categoryChips() {
    final l = L.of(context)!;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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

/// For You: artwork with a follow button on it, then the name and author.
class _DiscoverTile extends StatelessWidget {
  final UnifiedCastawayPodcast podcast;
  final bool following;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  const _DiscoverTile({required this.podcast, required this.following, required this.onOpen, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Semantics(
                button: true,
                label: podcast.title,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onOpen,
                  child: LazyNetworkImage(
                    imageUrl: podcast.artwork,
                    width: 116,
                    height: 116,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(top: 4, right: 4, child: _FollowButton(following: following, onPressed: onToggle, size: 36, filled: true)),
            ],
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(
              podcast.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: style.text),
            ),
          ),
          Text(
            podcast.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: style.muted),
          ),
        ],
      ),
    );
  }
}

/// Trending: rank, artwork, name and author, follow button.
class _TrendingRow extends StatelessWidget {
  final int rank;
  final UnifiedCastawayPodcast podcast;
  final bool following;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  const _TrendingRow({
    super.key,
    required this.rank,
    required this.podcast,
    required this.following,
    required this.onOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: style.muted),
              ),
            ),
            const SizedBox(width: 10),
            LazyNetworkImage(
              imageUrl: podcast.artwork,
              width: 54,
              height: 54,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    podcast.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: style.text),
                  ),
                  if (podcast.author.isNotEmpty)
                    Text(
                      podcast.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: style.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _FollowButton(following: following, onPressed: onToggle),
          ],
        ),
      ),
    );
  }
}

/// Round follow button: a plus to follow, a check once followed.
class _FollowButton extends StatelessWidget {
  final bool following;
  final VoidCallback onPressed;
  final double size;

  /// Solid background (drawn over artwork).
  final bool filled;

  const _FollowButton({required this.following, required this.onPressed, this.size = 44, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    final l = L.of(context)!;
    final Color bg = following ? style.accent : (filled ? castawayNavy : Colors.transparent);
    final Color fg = following ? style.onAccent : (filled ? Colors.white : style.text);
    return Tooltip(
      message: following ? l.unfollow : l.follow,
      child: Semantics(
        button: true,
        label: following ? l.unfollow : l.follow,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onPressed,
          radius: size / 2 + 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: following || filled ? null : Border.all(color: style.surfaceHigh, width: 2),
            ),
            child: Icon(
              following ? PhosphorIconsBold.check : PhosphorIconsBold.plus,
              size: size * 0.42,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
