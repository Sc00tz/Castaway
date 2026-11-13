// lib/ui/castaway/history.dart
import 'package:flutter/material.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/castaway/castaway_audio_service.dart';
import 'package:castaway_mobile/services/audio/audio_player_service.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/ui/widgets/episode_context_menu.dart';
import 'package:castaway_mobile/ui/castaway/podcast_nav.dart';
import 'package:castaway_mobile/ui/widgets/castaway_episode_card.dart';
import 'package:castaway_mobile/ui/castaway/episode_details.dart';
import 'package:castaway_mobile/ui/utils/local_download_utils.dart';
import 'package:castaway_mobile/ui/utils/player_utils.dart';
import 'package:castaway_mobile/ui/utils/position_utils.dart';
import 'package:castaway_mobile/ui/widgets/server_error_page.dart';
import 'package:castaway_mobile/services/error_handling_service.dart';
import 'package:castaway_mobile/services/global_services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:castaway_mobile/ui/widgets/soft_ui.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/ui/widgets/hide_played.dart';

/// Sort direction options for history episodes
enum HistorySortDirection {
  newestFirst,
  oldestFirst,
  shortestFirst,
  longestFirst,
  titleAZ,
  titleZA,
}

/// Episode filter options for history
enum HistoryFilter {
  all,
  completed,
  inProgress,
}

class CastawayHistory extends StatefulWidget {
  const CastawayHistory({Key? key}) : super(key: key);

  @override
  State<CastawayHistory> createState() => _CastawayHistoryState();
}

class _CastawayHistoryState extends State<CastawayHistory> with HidePlayed<CastawayHistory> {
  @override
  String get hidePlayedKey => 'history_hide_played';

  @override
  void onHidePlayedChanged() => _filterEpisodes();

  bool _isLoading = false;
  String _errorMessage = '';
  List<CastawayEpisode> _episodes = [];
  List<CastawayEpisode> _filteredEpisodes = [];
  // Position of each episode in [_episodes], for the context menu.
  Map<CastawayEpisode, int> _originalIndex = Map<CastawayEpisode, int>.identity();
  final CastawayService _castawayService = CastawayService();
  // Use global audio service instead of creating local instance
  int? _contextMenuEpisodeIndex;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Pagination state
  int _offset = 0;
  int _total = 0;
  bool _isLoadingMore = false;

  // Sort and filter state
  HistorySortDirection _sortDirection = HistorySortDirection.newestFirst;
  HistoryFilter _activeFilter = HistoryFilter.all;
  static const String _sortPreferenceKey = 'history_sort_direction';

  // Favorites-only filter (podcast-level favorite state from return_pods).
  bool _favoritesOnly = false;
  Set<int> _favoritePodcastIds = {};

  @override
  void initState() {
    super.initState();
    loadHidePlayed();
    _loadSortPreference();
    _loadHistory();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSort = prefs.getString(_sortPreferenceKey);
    if (savedSort != null) {
      setState(() {
        _sortDirection = _sortDirectionFromString(savedSort);
      });
    }
  }

  Future<void> _saveSortPreference(HistorySortDirection direction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPreferenceKey, _sortDirectionToString(direction));
  }

  String _sortDirectionToString(HistorySortDirection direction) {
    switch (direction) {
      case HistorySortDirection.newestFirst:
        return 'newest';
      case HistorySortDirection.oldestFirst:
        return 'oldest';
      case HistorySortDirection.shortestFirst:
        return 'shortest';
      case HistorySortDirection.longestFirst:
        return 'longest';
      case HistorySortDirection.titleAZ:
        return 'title_az';
      case HistorySortDirection.titleZA:
        return 'title_za';
    }
  }

  HistorySortDirection _sortDirectionFromString(String value) {
    switch (value) {
      case 'oldest':
        return HistorySortDirection.oldestFirst;
      case 'shortest':
        return HistorySortDirection.shortestFirst;
      case 'longest':
        return HistorySortDirection.longestFirst;
      case 'title_az':
        return HistorySortDirection.titleAZ;
      case 'title_za':
        return HistorySortDirection.titleZA;
      case 'newest':
      default:
        return HistorySortDirection.newestFirst;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Don't dispose global audio service - it should persist across pages
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterEpisodes();
    });
  }

  void _filterEpisodes() {
    // Sort and status filter are handled server-side; only apply search locally
    var filtered = List<CastawayEpisode>.from(_episodes);
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((episode) {
        return episode.episodeTitle.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               episode.podcastName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               episode.episodeDescription.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }
    if (_favoritesOnly) {
      filtered = filtered
          .where((e) =>
              e.podcastId != null && _favoritePodcastIds.contains(e.podcastId))
          .toList();
    }
    if (_activeFilter != HistoryFilter.completed) {
      filtered = withoutPlayed(filtered, (e) => e.completed);
    }
    _filteredEpisodes = filtered;
    _originalIndex = Map<CastawayEpisode, int>.identity()
      ..addEntries([for (var i = 0; i < _episodes.length; i++) MapEntry(_episodes[i], i)]);
  }

  Future<void> _loadFavoritePodcastIds(int userId) async {
    try {
      final podcasts = await _castawayService.getUserPodcasts(userId);
      if (!mounted) return;
      setState(() {
        _favoritePodcastIds = podcasts
            .where((p) => p.isFavorite && p.id != null)
            .map((p) => p.id!)
            .toSet();
        _filterEpisodes();
      });
    } catch (e) {
      // Non-fatal: favorites filter just won't have data.
    }
  }

  void _toggleFavoritesFilter() {
    setState(() {
      _favoritesOnly = !_favoritesOnly;
      _filterEpisodes();
    });
    if (_favoritesOnly) {
      final userId =
          Provider.of<SettingsBloc>(context, listen: false)
              .currentSettings
              .castawayUserId;
      if (userId != null) {
        _loadFavoritePodcastIds(userId);
      }
    }
  }

  String _sortByParam(HistorySortDirection direction) {
    switch (direction) {
      case HistorySortDirection.shortestFirst:
      case HistorySortDirection.longestFirst:
        return 'duration';
      case HistorySortDirection.titleAZ:
      case HistorySortDirection.titleZA:
        return 'title';
      default:
        return 'date';
    }
  }

  String _sortOrderParam(HistorySortDirection direction) {
    switch (direction) {
      case HistorySortDirection.oldestFirst:
      case HistorySortDirection.shortestFirst:
      case HistorySortDirection.titleAZ:
        return 'asc';
      default:
        return 'desc';
    }
  }

  String _filterParam(HistoryFilter filter) {
    switch (filter) {
      case HistoryFilter.completed: return 'completed';
      case HistoryFilter.inProgress: return 'in_progress';
      case HistoryFilter.all: return 'all';
    }
  }

  void _setSortDirection(HistorySortDirection direction) {
    setState(() {
      _sortDirection = direction;
      _episodes = [];
      _filteredEpisodes = [];
      _offset = 0;
      _total = 0;
    });
    _saveSortPreference(direction);
    _loadHistory();
  }

  void _setFilter(HistoryFilter filter) {
    setState(() {
      _activeFilter = filter;
      _episodes = [];
      _filteredEpisodes = [];
      _offset = 0;
      _total = 0;
    });
    _loadHistory();
  }

  void _clearAllFilters() {
    setState(() {
      _activeFilter = HistoryFilter.all;
      _favoritesOnly = false;
      resetHidePlayed();
      _searchController.clear();
      _searchQuery = '';
      _episodes = [];
      _filteredEpisodes = [];
      _offset = 0;
      _total = 0;
    });
    _loadHistory();
  }

  CastawayAudioService? get _audioService => GlobalServices.castawayAudioService;

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _offset = 0;
      _total = 0;
      _episodes = [];
      _filteredEpisodes = [];
    });

    try {
      final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
      final settings = settingsBloc.currentSettings;

      if (settings.castawayServer == null ||
          settings.castawayApiKey == null ||
          settings.castawayUserId == null) {
        setState(() {
          _errorMessage = L.of(context)!.not_connected_please_login;
          _isLoading = false;
        });
        return;
      }

      _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
      GlobalServices.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
      final userId = settings.castawayUserId!;

      final page = await _castawayService.getUserHistoryPaged(
        userId,
        limit: 50,
        offset: 0,
        sortBy: _sortByParam(_sortDirection),
        sortOrder: _sortOrderParam(_sortDirection),
        filter: _filterParam(_activeFilter),
      );

      final enrichedEpisodes = await PositionUtils.enrichEpisodesWithBestPositions(
        context,
        _castawayService,
        page.episodes,
        userId,
      );

      setState(() {
        _episodes = enrichedEpisodes;
        _total = page.total;
        _offset = enrichedEpisodes.length;
        _filterEpisodes();
        _isLoading = false;
      });

      await LocalDownloadUtils.loadLocalDownloadStatuses(context, enrichedEpisodes);
      await _loadFavoritePodcastIds(userId);
    } catch (e) {
      setState(() {
        _errorMessage = L.of(context)!.failed_to_load_history_error(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreEpisodes() async {
    if (_isLoadingMore || _offset >= _total) return;

    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;

    if (settings.castawayServer == null ||
        settings.castawayApiKey == null ||
        settings.castawayUserId == null) {
      return;
    }

    final userId = settings.castawayUserId!;
    setState(() => _isLoadingMore = true);

    try {
      final page = await _castawayService.getUserHistoryPaged(
        userId,
        limit: 50,
        offset: _offset,
        sortBy: _sortByParam(_sortDirection),
        sortOrder: _sortOrderParam(_sortDirection),
        filter: _filterParam(_activeFilter),
      );

      final enrichedEpisodes = await PositionUtils.enrichEpisodesWithBestPositions(
        context,
        _castawayService,
        page.episodes,
        userId,
      );

      setState(() {
        _episodes.addAll(enrichedEpisodes);
        _total = page.total;
        _offset += enrichedEpisodes.length;
        _filterEpisodes();
        _isLoadingMore = false;
      });

      await LocalDownloadUtils.loadLocalDownloadStatuses(context, enrichedEpisodes);
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    LocalDownloadUtils.clearCache();
    await _loadHistory();
  }

  Future<void> _playEpisode(CastawayEpisode episode) async {
    
    if (_audioService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L.of(context)!.audio_service_not_available),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _audioService!.playCastawayEpisode(
        castawayEpisode: episode,
        resume: episode.isStarted,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L.current.failed_to_play_episode(e.toString())),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showContextMenu(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    final isDownloadedLocally = await LocalDownloadUtils.isEpisodeDownloadedLocally(context, episode);

    if (!mounted) return;

    final pageContext = context;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => EpisodeContextMenu(
        episode: episode,
        isDownloadedLocally: isDownloadedLocally,
        onSave: () {
          Navigator.of(context).pop();
          _saveEpisode(episodeIndex);
        },
        onRemoveSaved: () {
          Navigator.of(context).pop();
          _removeSavedEpisode(episodeIndex);
        },
        onDownload: episode.downloaded 
          ? () {
              Navigator.of(context).pop();
              _deleteEpisode(episodeIndex);
            }
          : () {
              Navigator.of(context).pop();
              _downloadEpisode(episodeIndex);
            },
        onLocalDownload: () {
          Navigator.of(context).pop();
          _localDownloadEpisode(episodeIndex);
        },
        onDeleteLocalDownload: () {
          Navigator.of(context).pop();
          _deleteLocalDownload(episodeIndex);
        },
        onQueue: () {
          Navigator.of(context).pop();
          _toggleQueueEpisode(episodeIndex);
        },
        onQueueAt: (position) {
          Navigator.of(context).pop();
          _toggleQueueEpisode(episodeIndex, position: position);
        },
        onMarkComplete: () {
          Navigator.of(context).pop();
          _toggleMarkComplete(episodeIndex);
        },
        onDismiss: () {
          Navigator.of(context).pop();
        },
        onPodcastTap: () {
          Navigator.of(context).pop();
          navigateToPodcastById(
            pageContext,
            episode.podcastId,
            fallbackTitle: episode.podcastName,
            fallbackArtwork: episode.episodeArtwork,
          );
        },
      ),
    );
  }

  Future<void> _localDownloadEpisode(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    
    final success = await LocalDownloadUtils.localDownloadEpisode(context, episode);
    
    if (success) {
      LocalDownloadUtils.showSnackBar(context, L.current.episode_download_started, Colors.green);
    } else {
      LocalDownloadUtils.showSnackBar(context, L.current.failed_to_start_download, Colors.red);
    }
  }

  Future<void> _deleteLocalDownload(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    
    final deletedCount = await LocalDownloadUtils.deleteLocalDownload(context, episode);
    
    if (deletedCount > 0) {
      LocalDownloadUtils.showSnackBar(
        context, 
        L.current.deleted_local_downloads(deletedCount), 
        Colors.orange
      );
    } else {
      LocalDownloadUtils.showSnackBar(context, L.current.local_download_not_found, Colors.red);
    }
  }

  void _hideContextMenu() {
    setState(() {
      _contextMenuEpisodeIndex = null;
    });
  }

  Future<void> _saveEpisode(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);

    try {
      final success = await _castawayService.saveEpisode(
        episode.episodeId,
        userId,
        episode.isYoutube,
      );

      if (success) {
        setState(() {
          _episodes[episodeIndex] = _updateEpisodeProperty(_episodes[episodeIndex], saved: true);
          _filterEpisodes(); // Update filtered list to reflect changes
        });
        _showSnackBar(L.current.episode_saved, Colors.green);
      } else {
        _showSnackBar(L.current.failed_to_save_episode, Colors.red);
      }
    } catch (e) {
      _showSnackBar(L.current.error_saving_episode(e.toString()), Colors.red);
    }

    _hideContextMenu();
  }

  Future<void> _removeSavedEpisode(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);

    try {
      final success = await _castawayService.removeSavedEpisode(
        episode.episodeId,
        userId,
        episode.isYoutube,
      );

      if (success) {
        setState(() {
          _episodes[episodeIndex] = _updateEpisodeProperty(_episodes[episodeIndex], saved: false);
          _filterEpisodes(); // Update filtered list to reflect changes
        });
        _showSnackBar(L.current.removed_from_saved_episodes, Colors.orange);
      } else {
        _showSnackBar(L.current.failed_to_remove_saved_episode, Colors.red);
      }
    } catch (e) {
      _showSnackBar(L.current.error_removing_saved_episode(e.toString()), Colors.red);
    }

    _hideContextMenu();
  }

  Future<void> _downloadEpisode(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);

    try {
      final success = await _castawayService.downloadEpisode(
        episode.episodeId,
        userId,
        episode.isYoutube,
      );

      if (success) {
        setState(() {
          _episodes[episodeIndex] = _updateEpisodeProperty(episode, downloaded: true);
          _filterEpisodes(); // Update filtered list to reflect changes
        });
        _showSnackBar(L.current.episode_download_queued, Colors.green);
      } else {
        _showSnackBar(L.current.failed_to_queue_download, Colors.red);
      }
    } catch (e) {
      _showSnackBar(L.current.error_downloading_episode(e.toString()), Colors.red);
    }

    _hideContextMenu();
  }

  Future<void> _deleteEpisode(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);

    try {
      final success = await _castawayService.deleteEpisode(
        episode.episodeId,
        userId,
        episode.isYoutube,
      );

      if (success) {
        setState(() {
          _episodes[episodeIndex] = _updateEpisodeProperty(episode, downloaded: false);
          _filterEpisodes(); // Update filtered list to reflect changes
        });
        _showSnackBar(L.current.episode_deleted_from_server, Colors.orange);
      } else {
        _showSnackBar(L.current.failed_to_delete_episode, Colors.red);
      }
    } catch (e) {
      _showSnackBar(L.current.error_deleting_episode(e.toString()), Colors.red);
    }

    _hideContextMenu();
  }

  Future<void> _toggleQueueEpisode(int episodeIndex, {String? position}) async {
    final episode = _episodes[episodeIndex];
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);

    try {
      bool success;
      if (episode.queued) {
        success = await _castawayService.removeQueuedEpisode(
          episode.episodeId,
          userId,
          episode.isYoutube,
        );
        if (success) {
          setState(() {
            _episodes[episodeIndex] = _updateEpisodeProperty(episode, queued: false);
            _filterEpisodes(); // Update filtered list to reflect changes
          });
          _showSnackBar(L.current.removed_from_queue, Colors.orange);
        }
      } else {
        success = await _castawayService.queueEpisode(
          episode.episodeId,
          userId,
          episode.isYoutube,
          position: position,
        );
        if (success) {
          setState(() {
            _episodes[episodeIndex] = _updateEpisodeProperty(episode, queued: true);
            _filterEpisodes(); // Update filtered list to reflect changes
          });
          _showSnackBar(L.current.added_to_queue_excl, Colors.green);
        }
      }

      if (!success) {
        _showSnackBar(L.current.failed_to_update_queue, Colors.red);
      }
    } catch (e) {
      _showSnackBar(L.current.error_updating_queue(e.toString()), Colors.red);
    }

    _hideContextMenu();
  }

  Future<void> _toggleMarkComplete(int episodeIndex) async {
    final episode = _episodes[episodeIndex];
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);

    try {
      bool success;
      if (episode.completed) {
        success = await _castawayService.markEpisodeUncompleted(
          episode.episodeId,
          userId,
          episode.isYoutube,
        );
        if (success) {
          setState(() {
            _episodes[episodeIndex] = _updateEpisodeProperty(episode, completed: false);
            _filterEpisodes(); // Update filtered list to reflect changes
          });
          _showSnackBar(L.current.marked_as_incomplete, Colors.orange);
        }
      } else {
        success = await _castawayService.markEpisodeCompleted(
          episode.episodeId,
          userId,
          episode.isYoutube,
        );
        if (success) {
          setState(() {
            _episodes[episodeIndex] = _updateEpisodeProperty(episode, completed: true);
            _filterEpisodes(); // Update filtered list to reflect changes
          });
          _showSnackBar(L.current.marked_as_complete, Colors.green);
        }
      }

      if (!success) {
        _showSnackBar(L.current.failed_to_update_completion, Colors.red);
      }
    } catch (e) {
      _showSnackBar(L.current.error_updating_completion(e.toString()), Colors.red);
    }

    _hideContextMenu();
  }

  CastawayEpisode _updateEpisodeProperty(
    CastawayEpisode episode, {
    bool? saved,
    bool? downloaded,
    bool? queued,
    bool? completed,
  }) {
    return CastawayEpisode(
      podcastName: episode.podcastName,
      episodeTitle: episode.episodeTitle,
      episodePubDate: episode.episodePubDate,
      episodeDescription: episode.episodeDescription,
      episodeArtwork: episode.episodeArtwork,
      episodeUrl: episode.episodeUrl,
      episodeDuration: episode.episodeDuration,
      listenDuration: episode.listenDuration,
      episodeId: episode.episodeId,
      completed: completed ?? episode.completed,
      saved: saved ?? episode.saved,
      queued: queued ?? episode.queued,
      downloaded: downloaded ?? episode.downloaded,
      isYoutube: episode.isYoutube,
      listenDate: episode.listenDate,
    );
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(L.of(context)!.loading_listening_history),
            ],
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return SliverServerErrorPage(
        errorMessage: _errorMessage.isServerConnectionError 
          ? null 
          : _errorMessage,
        onRetry: _refresh,
        title: L.of(context)!.history_unavailable,
        subtitle: _errorMessage.isServerConnectionError
          ? L.of(context)!.unable_to_connect_server
          : L.of(context)!.failed_to_load_history,
      );
    }

    if (_episodes.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: SoftEmptyState(
            icon: PhosphorIconsRegular.clockCounterClockwise,
            title: L.of(context)!.no_listening_history,
            body: L.of(context)!.history_empty_body,
          ),
        ),
      );
    }

    return MultiSliver(
      children: [
        SliverToBoxAdapter(
          child: SoftSectionHeader(
            title: L.of(context)!.history,
            count: _filteredEpisodes.length,
            trailing: [
              IconButton(
                tooltip: L.of(context)!.refresh,
                icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        ListToolbar.sliver(context, _buildToolbar()),
        _buildEpisodesList(),
      ],
    );
  }

  ListToolbar<HistorySortDirection> _buildToolbar() {
    return ListToolbar<HistorySortDirection>(
      searchController: _searchController,
      searchHint: L.of(context)!.search_episodes_label,
      filters: [
        ToolbarFilter(
          label: L.of(context)!.filter_all,
          selected: _activeFilter == HistoryFilter.all && !_favoritesOnly,
          onTap: _clearAllFilters,
        ),
        ToolbarFilter(
          label: L.of(context)!.filter_in_progress,
          selected: _activeFilter == HistoryFilter.inProgress,
          onTap: () => _setFilter(
              _activeFilter == HistoryFilter.inProgress ? HistoryFilter.all : HistoryFilter.inProgress),
        ),
        ToolbarFilter(
          label: L.of(context)!.completed,
          selected: _activeFilter == HistoryFilter.completed,
          onTap: () => _setFilter(
              _activeFilter == HistoryFilter.completed ? HistoryFilter.all : HistoryFilter.completed),
        ),
        ToolbarFilter(
          label: L.of(context)!.favorites,
          icon: _favoritesOnly ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
          selected: _favoritesOnly,
          onTap: _toggleFavoritesFilter,
        ),
        hidePlayedFilter(context),
      ],
      sortOptions: {
        HistorySortDirection.newestFirst: L.of(context)!.sort_newest_first,
        HistorySortDirection.oldestFirst: L.of(context)!.sort_oldest_first,
        HistorySortDirection.shortestFirst: L.of(context)!.sort_shortest_first,
        HistorySortDirection.longestFirst: L.of(context)!.sort_longest_first,
        HistorySortDirection.titleAZ: L.of(context)!.sort_title_az,
        HistorySortDirection.titleZA: L.of(context)!.sort_title_za,
      },
      sortValue: _sortDirection,
      onSort: _setSortDirection,
    );
  }

  Widget _buildEpisodesList() {
    final hasActiveSearch = _searchQuery.isNotEmpty;
    if (_filteredEpisodes.isEmpty &&
        !_isLoadingMore &&
        (hasActiveSearch || _favoritesOnly || hidePlayed)) {
      return SliverToBoxAdapter(
        child: SoftEmptyState(
          icon: PhosphorIconsRegular.funnelSimpleX,
          title: L.of(context)!.no_episodes_found,
          body: _getNoResultsMessage(),
          action: TextButton(onPressed: _clearAllFilters, child: Text(L.of(context)!.clear_filters)),
        ),
      );
    }

    final showFooter = _isLoadingMore || _offset < _total;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final episodeIndex = index;

          // Footer: triggers load more when it becomes visible
          if (showFooter && episodeIndex == _filteredEpisodes.length) {
            if (!_isLoadingMore) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _loadMoreEpisodes());
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (episodeIndex >= _filteredEpisodes.length) return null;
          final episode = _filteredEpisodes[episodeIndex];
          final originalIndex = _originalIndex[episode] ?? -1;
          return CastawayEpisodeCard(
            episode: episode,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CastawayEpisodeDetails(
                    initialEpisode: episode,
                  ),
                ),
              );
            },
            onLongPress: originalIndex >= 0 ? () => _showContextMenu(originalIndex) : null,
            onPlayPressed: () => _playEpisode(episode),
          );
        },
        childCount: _filteredEpisodes.length + (showFooter ? 1 : 0),
      ),
    );
  }

  String _getNoResultsMessage() {
    final l = L.of(context)!;
    final hasQuery = _searchQuery.isNotEmpty;
    if (_activeFilter == HistoryFilter.completed) {
      return hasQuery ? l.no_completed_episodes_match_query(_searchQuery) : l.no_completed_episodes;
    }
    if (_activeFilter == HistoryFilter.inProgress) {
      return hasQuery ? l.no_in_progress_episodes_match_query(_searchQuery) : l.no_in_progress_episodes;
    }
    return hasQuery ? l.no_episodes_match_query(_searchQuery) : l.no_episodes_match_filters;
  }
}