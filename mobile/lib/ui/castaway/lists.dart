// The Lists tab (2026-11 redesign): every episode list in one place. Home,
// New Releases (the feed), In Progress, Up Next, Saved, Downloads, History and
// the user's playlists, each opening as its own page.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/home_data.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/castaway/create_playlist.dart';
import 'package:castaway_mobile/ui/castaway/feed.dart';
import 'package:castaway_mobile/ui/castaway/history.dart';
import 'package:castaway_mobile/ui/castaway/home.dart';
import 'package:castaway_mobile/ui/castaway/playlist_episodes.dart';
import 'package:castaway_mobile/ui/castaway/queue.dart';
import 'package:castaway_mobile/ui/castaway/saved.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/ui/library/downloads.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';
import 'package:sliver_tools/sliver_tools.dart';

/// The server's built-in playlist of episodes started but not finished.
const String inProgressPlaylistName = 'Currently Listening'; // i18n-ignore

enum CastawayListPage { home, newReleases, upNext, saved, downloads, history }

String _pageTitle(BuildContext context, CastawayListPage page) {
  final l = L.of(context)!;
  return switch (page) {
    CastawayListPage.home => l.nav_home,
    CastawayListPage.newReleases => l.list_new_releases,
    CastawayListPage.upNext => l.up_next_queue_label,
    CastawayListPage.saved => l.saved,
    CastawayListPage.downloads => l.downloads,
    CastawayListPage.history => l.history,
  };
}

Widget _pageSliver(CastawayListPage page) => switch (page) {
      CastawayListPage.home => const CastawayHome(),
      CastawayListPage.newReleases => const CastawayFeed(),
      CastawayListPage.upNext => const CastawayQueue(),
      CastawayListPage.saved => const CastawaySaved(),
      CastawayListPage.downloads => const Downloads(),
      CastawayListPage.history => const CastawayHistory(),
    };

/// Push one of the lists as a page with its own title bar.
Future<void> openListPage(BuildContext context, CastawayListPage page) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: RouteSettings(name: 'list-${page.name}'),
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(_pageTitle(context, page))),
        body: CustomScrollView(slivers: [_pageSliver(page)]),
      ),
    ),
  );
}

class CastawayLists extends StatefulWidget {
  /// Tests pass their own client and user; the app uses the signed-in server.
  final CastawayService? service;
  final int? userId;

  const CastawayLists({super.key, this.service, this.userId});

  @override
  State<CastawayLists> createState() => _CastawayListsState();
}

class _CastawayListsState extends State<CastawayLists> {
  late final CastawayService _service = widget.service ?? CastawayService();
  HomeOverview? _overview;
  List<PlaylistData>? _playlists;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Counts and playlists; a failure leaves the rows without counts.
  Future<void> _load() async {
    int? userId = widget.userId;
    if (widget.service == null) {
      final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
      userId = settings.castawayUserId;
      if (settings.castawayServer == null || settings.castawayApiKey == null || userId == null) return;
      _service.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
    }
    if (userId == null) return;

    try {
      final playlists = await _service.getUserPlaylists(userId);
      if (mounted) setState(() => _playlists = playlists);
    } catch (_) {}
    try {
      final overview = await _service.getHomeOverview(userId);
      if (mounted) setState(() => _overview = overview);
    } catch (_) {}
  }

  /// Each account gets its own copy of the built-in playlists, not flagged as
  /// built-in, so this goes by name.
  PlaylistData? get _inProgress => _playlists?.where((p) => p.name == inProgressPlaylistName).firstOrNull;

  Future<void> _open(CastawayListPage page) async {
    await openListPage(context, page);
    if (mounted) _load();
  }

  Future<void> _openPlaylist(PlaylistData? playlist) async {
    if (playlist == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.of(context)!.list_unavailable)));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (context) => PlaylistEpisodesPage(playlist: playlist)),
    );
    if (mounted) _load();
  }

  Future<void> _newPlaylist() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CreatePlaylistPage()),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final style = CastawayStyle.of(context);
    final overview = _overview;
    final others = (_playlists ?? const <PlaylistData>[]).where((p) => p != _inProgress).toList();

    // Fixed tile colours (brand blue, orange, sand and three companions).
    const blue = Color(0xff169dca), orange = Color(0xffee6747), sand = Color(0xffe7d8c5);
    const mustard = Color(0xffb8892f), teal = Color(0xff2f6f5e), purple = Color(0xff6b4f8a);

    return MultiSliver(children: [
      SliverToBoxAdapter(child: TabHeader(title: l.nav_lists)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList.list(children: [
          _ListRow(
            key: const ValueKey('list-home'),
            icon: PhosphorIconsBold.house,
            tint: style.surfaceHigh,
            title: l.nav_home,
            onTap: () => _open(CastawayListPage.home),
          ),
          _ListRow(
            key: const ValueKey('list-newReleases'),
            icon: PhosphorIconsBold.sparkle,
            tint: blue,
            title: l.list_new_releases,
            onTap: () => _open(CastawayListPage.newReleases),
          ),
          _ListRow(
            key: const ValueKey('list-inProgress'),
            icon: PhosphorIconsBold.clockClockwise,
            tint: orange,
            title: l.list_in_progress,
            count: _inProgress?.episodeCount,
            onTap: () => _openPlaylist(_inProgress),
          ),
          _ListRow(
            key: const ValueKey('list-upNext'),
            icon: PhosphorIconsBold.queue,
            tint: sand,
            title: l.up_next_queue_label,
            count: overview?.queueCount,
            onTap: () => _open(CastawayListPage.upNext),
          ),
          _ListRow(
            key: const ValueKey('list-saved'),
            icon: PhosphorIconsBold.star,
            tint: mustard,
            title: l.saved,
            count: overview?.savedCount,
            onTap: () => _open(CastawayListPage.saved),
          ),
          _ListRow(
            key: const ValueKey('list-downloads'),
            icon: PhosphorIconsBold.downloadSimple,
            tint: teal,
            title: l.downloads,
            onTap: () => _open(CastawayListPage.downloads),
          ),
          _ListRow(
            key: const ValueKey('list-history'),
            icon: PhosphorIconsBold.clockCounterClockwise,
            tint: purple,
            title: l.history,
            onTap: () => _open(CastawayListPage.history),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
            child: Semantics(
              header: true,
              child: Text(
                l.your_playlists.toUpperCase(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: style.muted),
              ),
            ),
          ),
          for (final playlist in others)
            _ListRow(
              icon: PhosphorIconsBold.playlist,
              tint: null,
              title: playlist.name,
              count: playlist.episodeCount,
              onTap: () => _openPlaylist(playlist),
            ),
          _NewPlaylistRow(onTap: _newPlaylist),
          const SizedBox(height: 16),
        ]),
      ),
    ]);
  }
}

class _ListRow extends StatelessWidget {
  final IconData icon;

  /// Tile fill; null draws an outlined tile in the link colour (playlists).
  final Color? tint;
  final String title;
  final int? count;
  final VoidCallback onTap;

  const _ListRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    final fill = tint;
    return Semantics(
      button: true,
      label: count == null ? title : '$title, $count',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(10),
                    border: fill == null ? Border.all(color: style.link, width: 2) : null,
                  ),
                  child: Icon(icon, size: 20, color: fill == null ? style.link : inkOn(fill)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: style.text),
                  ),
                ),
                if (count != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 14,
                        color: style.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(PhosphorIconsRegular.caretRight, size: 18, color: style.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewPlaylistRow extends StatelessWidget {
  final VoidCallback onTap;

  const _NewPlaylistRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return Semantics(
      button: true,
      label: L.of(context)!.new_playlist,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('list-newPlaylist'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: style.link, width: 2),
                  ),
                  child: Icon(PhosphorIconsBold.plus, size: 18, color: style.link),
                ),
                const SizedBox(width: 14),
                Text(
                  L.of(context)!.new_playlist,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: style.link),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
