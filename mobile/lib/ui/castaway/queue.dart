// lib/ui/castaway/queue.dart
import 'package:flutter/material.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/castaway/castaway_audio_service.dart';
import 'package:castaway_mobile/services/auto_download/queue_download_service.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/ui/widgets/episode_context_menu.dart';
import 'package:castaway_mobile/ui/castaway/podcast_nav.dart';
import 'package:castaway_mobile/ui/widgets/draggable_queue_episode_card.dart';
import 'package:castaway_mobile/ui/castaway/episode_details.dart';
import 'package:castaway_mobile/ui/utils/local_download_utils.dart';
import 'package:castaway_mobile/ui/utils/position_utils.dart';
import 'package:castaway_mobile/services/global_services.dart';
import 'package:provider/provider.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/ui/widgets/soft_ui.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/ui/widgets/hide_played.dart';
import 'package:castaway_mobile/ui/widgets/live_positions.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';

class CastawayQueue extends StatefulWidget {
  const CastawayQueue({Key? key}) : super(key: key);

  @override
  State<CastawayQueue> createState() => _CastawayQueueState();
}

class _CastawayQueueState extends State<CastawayQueue> with HidePlayed<CastawayQueue>, LivePositions<CastawayQueue> {
  @override
  String get hidePlayedKey => 'queue_hide_played';

  /// Indices into [_episodes] that are shown (all of them unless played ones are hidden), so
  /// index-based handlers keep addressing [_episodes].
  List<int> get _visibleIndices => [
        for (var i = 0; i < _episodes.length; i++)
          if (!(hidePlayed && _episodes[i].completed)) i,
      ];

  /// A drag within the shown episodes, applied to the whole queue: the moved episode goes just
  /// before the one it was dropped on (or after the last shown one).
  void _reorderVisible(int oldIndex, int newIndex) {
    final (from, to) = visibleMoveToFull(_visibleIndices, oldIndex, newIndex);
    _reorderEpisodes(from, to);
  }

  bool _isLoading = false;
  String _errorMessage = '';
  List<CastawayEpisode> _episodes = [];

  @override
  bool applyLivePosition(PositionUpdate update) {
    final updated = PositionUtils.applyUpdate(_episodes, update);
    if (identical(updated, _episodes)) return false;
    _episodes = updated;
    return true;
  }
  final CastawayService _castawayService = CastawayService();
  // Use global audio service instead of creating local instance
  int? _contextMenuEpisodeIndex;

  @override
  void initState() {
    super.initState();
    loadHidePlayed();
    _loadQueuedEpisodes();
  }

  CastawayAudioService? get _audioService => GlobalServices.castawayAudioService;

  Future<void> _loadQueuedEpisodes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
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

      final episodes = await _castawayService.getQueuedEpisodes(userId);
      
      // Enrich episodes with best available positions (local vs server)
      final enrichedEpisodes = await PositionUtils.enrichEpisodesWithBestPositions(
        context,
        _castawayService,
        episodes,
        userId,
      );
      
      setState(() {
        _episodes = withLivePositions(enrichedEpisodes);
        _isLoading = false;
      });
      
      // After loading episodes, check their local download status
      await LocalDownloadUtils.loadLocalDownloadStatuses(context, enrichedEpisodes);
    } catch (e) {
      setState(() {
        _errorMessage = L.of(context)!.failed_to_load_queue_error(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    // Clear local download status cache on refresh
    LocalDownloadUtils.clearCache();
    await _loadQueuedEpisodes();
  }

  /// Fire-and-forget re-sync of the auto-download queue after the queue changes.
  void _syncQueueDownloads() {
    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
    if (settings.castawayUserId == null) return;
    QueueDownloadService.syncQueueDownloads(
      context: context,
      castawayService: _castawayService,
      userId: settings.castawayUserId!,
    );
  }

  Future<void> _reorderEpisodes(int oldIndex, int newIndex) async {
    // Adjust indices if moving down the list
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // Update local state immediately for smooth UI
    setState(() {
      final episode = _episodes.removeAt(oldIndex);
      _episodes.insert(newIndex, episode);
    });

    // Get episodes in new order, keeping is_youtube so colliding podcast/YouTube
    // ids are repositioned correctly.
    final reorderItems = _episodes
        .map((e) => (episodeId: e.episodeId, isYoutube: e.isYoutube))
        .toList();

    // Call API to update order on server
    try {
      final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
      final settings = settingsBloc.currentSettings;
      final userId = settings.castawayUserId;

      if (userId == null) {
        _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
        // Reload to restore original order if API call fails
        await _loadQueuedEpisodes();
        return;
      }

      _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
      final success = await _castawayService.reorderQueue(userId, reorderItems);

      if (!success) {
        _showSnackBar(L.current.failed_to_update_queue_order, Colors.red);
        // Reload to restore original order if API call fails
        await _loadQueuedEpisodes();
      } else {
        _syncQueueDownloads();
      }
    } catch (e) {
      _showSnackBar(L.current.error_updating_queue_order(e.toString()), Colors.red);
      // Reload to restore original order if API call fails
      await _loadQueuedEpisodes();
    }
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
      barrierColor: Colors.black.withValues(alpha: 0.3),
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

  Future<void> _toggleQueueEpisode(int episodeIndex) async {
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
          // REMOVE the episode from the list since it's no longer queued
          setState(() {
            _episodes.removeAt(episodeIndex);
          });
          _showSnackBar(L.current.removed_from_queue, Colors.orange);
          _syncQueueDownloads();
        }
      } else {
        // This shouldn't happen since all episodes here are already queued
        // But just in case, we'll handle it
        success = await _castawayService.queueEpisode(
          episode.episodeId,
          userId,
          episode.isYoutube,
        );
        if (success) {
          setState(() {
            _episodes[episodeIndex] = _updateEpisodeProperty(episode, queued: true);
          });
          _showSnackBar(L.current.added_to_queue_excl, Colors.green);
          _syncQueueDownloads();
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
  void dispose() {
    // Don't dispose global audio service - it should persist across pages
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: SoftEmptyState(
            icon: PhosphorIconsRegular.warningCircle,
            title: L.of(context)!.couldnt_load_queue,
            body: _errorMessage,
            action: FilledButton.tonal(onPressed: _refresh, child: Text(L.of(context)!.retry)),
          ),
        ),
      );
    }

    if (_episodes.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: SoftEmptyState(
            icon: PhosphorIconsRegular.queue,
            title: L.of(context)!.queue_empty,
            body: L.of(context)!.queue_empty_body,
          ),
        ),
      );
    }

    return _buildEpisodesList();
  }

  Widget _buildEpisodesList() {
    final visible = _visibleIndices;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SoftSectionHeader(
            title: L.of(context)!.queue,
            count: _episodes.length,
            trailing: [
              IconButton(
                tooltip: L.of(context)!.refresh,
                icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        ListToolbar.sliver(context, ListToolbar<void>(filters: [hidePlayedFilter(context)])),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: SoftEmptyState(
              icon: PhosphorIconsRegular.checkCircle,
              title: L.of(context)!.no_episodes_match_filter,
            ),
          )
        else
          // Lazily built; auto-scrolls when a dragged card nears an edge.
          SliverReorderableList(
            onReorder: _reorderVisible,
            itemCount: visible.length,
            proxyDecorator: (child, index, animation) => Material(
              type: MaterialType.transparency,
              child: child,
            ),
            itemBuilder: (context, index) {
              final episodeIndex = visible[index];
              final episode = _episodes[episodeIndex];
              return Padding(
                key: ValueKey(episode.episodeId),
                padding: const EdgeInsets.only(bottom: 4),
                child: DraggableQueueEpisodeCard(
                  episode: episode,
                  index: index,
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
                  onLongPress: () => _showContextMenu(episodeIndex),
                  onPlayPressed: () => _playEpisode(episode),
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}
