// lib/ui/castaway/episode_details.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/castaway/castaway_audio_service.dart';
import 'package:castaway_mobile/services/audio/audio_player_service.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/entities/pending_action.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/entities/people.dart';
import 'package:castaway_mobile/ui/widgets/podcast_html.dart';
import 'package:castaway_mobile/ui/widgets/episode_description.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:castaway_mobile/ui/castaway/podcast_nav.dart';
import 'package:castaway_mobile/ui/castaway/people/people_widgets.dart';
import 'package:castaway_mobile/ui/utils/player_utils.dart';
import 'package:castaway_mobile/ui/utils/local_download_utils.dart';
import 'package:castaway_mobile/ui/utils/action_guard.dart';
import 'package:castaway_mobile/ui/utils/artwork_colors.dart';
import 'package:castaway_mobile/ui/widgets/lazy_network_image.dart';
import 'package:castaway_mobile/ui/widgets/soft_ui.dart';
import 'package:castaway_mobile/ui/widgets/castaway_episode_card.dart' show humanDuration;
import 'package:castaway_mobile/services/global_services.dart';
import 'package:provider/provider.dart';
import 'package:castaway_mobile/services/audio/audio_player_service.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/ui/castaway/collection_sheets.dart';

class CastawayEpisodeDetails extends StatefulWidget {
  final CastawayEpisode initialEpisode;

  const CastawayEpisodeDetails({
    Key? key,
    required this.initialEpisode,
  }) : super(key: key);

  @override
  State<CastawayEpisodeDetails> createState() => _CastawayEpisodeDetailsState();
}

class _CastawayEpisodeDetailsState extends State<CastawayEpisodeDetails> {
  final CastawayService _castawayService = CastawayService();
  // Use global audio service instead of creating local instance
  CastawayEpisode? _episode;
  bool _isLoading = true;
  String _errorMessage = '';
  List<CreditedPerson> _people = [];
  // True once people loaded from a server that supports adding them.
  bool _isDownloadedLocally = false;

  // Play-button loading feedback: true while we've kicked off playback for this
  // episode but the audio system hasn't yet acknowledged it as now-playing.
  bool _isStartingPlayback = false;
  Color? _artColor;
  AudioPlayerService? _audioPlayerService;
  StreamSubscription? _episodeSub;
  StreamSubscription? _stateSub;

  /// Guards the action buttons (play, save, queue, download, complete, local
  /// download) against re-entrant taps. Each of those handlers awaits at
  /// least one network call with no immediate visual feedback, so without
  /// this a slow response invites the user to tap again - firing a second,
  /// overlapping request that can race with the first (e.g. double-toggling
  /// a save/queue state).
  final ActionGuard _actionGuard = ActionGuard();

  @override
  void initState() {
    super.initState();
    _episode = widget.initialEpisode;
    _loadEpisodeDetails();
    _checkLocalDownloadStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_audioPlayerService != null) return;
    _resolveArtColor();
    final aps = Provider.of<AudioPlayerService>(context, listen: false);
    _audioPlayerService = aps;

    // Clear the loading state once the audio system reports this episode as the
    // now-playing one (mirrors CastawayEpisodeCard's behaviour).
    _episodeSub = aps.episodeEvent?.listen((episode) {
      if (!mounted) return;
      if (episode != null &&
          _episode != null &&
          episode.guid == _episode!.episodeUrl) {
        if (_isStartingPlayback) {
          setState(() => _isStartingPlayback = false);
        }
      }
    });

    // Safety: never leave the spinner stuck if playback errors out.
    _stateSub = aps.playingState?.listen((state) {
      if (!mounted) return;
      if (state == AudioState.error && _isStartingPlayback) {
        setState(() => _isStartingPlayback = false);
      }
    });
  }

  CastawayAudioService? get _audioService => GlobalServices.castawayAudioService;

  /// Run [action] only if no other guarded action is currently in flight.
  Future<void> _runGuarded(Future<void> Function() action) {
    return _actionGuard.run(action, onChange: () {
      if (mounted) setState(() {});
    });
  }

  /// Enqueue an interaction in the offline outbox so it syncs when back online,
  /// used when a direct server call fails (e.g. the device is offline). Returns
  /// true if it was queued.
  Future<bool> _enqueueOffline(PendingActionType type, int userId) async {
    final queue = GlobalServices.offlineActionQueue;
    if (queue == null) return false;
    await queue.enqueueSimple(type, _episode!.episodeId, userId, _episode!.isYoutube);
    return true;
  }

  Future<void> _checkLocalDownloadStatus() async {
    if (_episode == null) return;
    
    final isDownloaded = await LocalDownloadUtils.isEpisodeDownloadedLocally(context, _episode!);
    
    if (mounted) {
      setState(() {
        _isDownloadedLocally = isDownloaded;
      });
    }
  }

  Future<void> _localDownloadEpisode() async {
    if (_episode == null) return;
    
    final success = await LocalDownloadUtils.localDownloadEpisode(context, _episode!);
    
    if (success) {
      LocalDownloadUtils.showSnackBar(context, L.current.episode_download_started, Colors.green);
      await _checkLocalDownloadStatus(); // Update button state
    } else {
      LocalDownloadUtils.showSnackBar(context, L.current.failed_to_start_download, Colors.red);
    }
  }

  Future<void> _deleteLocalDownload() async {
    if (_episode == null) return;
    
    final deletedCount = await LocalDownloadUtils.deleteLocalDownload(context, _episode!);
    
    if (deletedCount > 0) {
      LocalDownloadUtils.showSnackBar(
        context, 
        L.current.deleted_local_downloads(deletedCount), 
        Colors.orange
      );
      await _checkLocalDownloadStatus(); // Update button state
    } else {
      LocalDownloadUtils.showSnackBar(context, L.current.local_download_not_found, Colors.red);
    }
  }

  Future<void> _shareEpisode() async {
    if (_episode == null) return;

    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
    if (settings.castawayServer == null || settings.castawayApiKey == null) {
      _showSnackBar(L.of(context)!.not_connected_to_server, Colors.red);
      return;
    }

    _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
    _showSnackBar(L.of(context)!.creating_share_link, Colors.blueGrey);

    try {
      final urlKey = await _castawayService.createShareLink(_episode!.episodeId);
      final shareUrl = '${settings.castawayServer}/shared_episode/$urlKey';
      if (!mounted) return;
      await _showShareDialog(shareUrl);
    } catch (e) {
      if (mounted) _showSnackBar(L.of(context)!.failed_to_create_share_link(e.toString()), Colors.red);
    }
  }

  Future<void> _showShareDialog(String shareUrl) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.of(context)!.share_episode_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L.of(context)!.share_link_description,
            ),
            const SizedBox(height: 12),
            SelectableText(
              shareUrl,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: shareUrl));
              _showSnackBar(L.of(context)!.link_copied, Colors.green);
            },
            icon: const Icon(PhosphorIconsRegular.copy),
            label: Text(L.of(context)!.copy),
          ),
          TextButton.icon(
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(text: shareUrl, subject: _episode?.episodeTitle),
              );
            },
            icon: const Icon(PhosphorIconsRegular.export),
            label: Text(L.of(context)!.share),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(L.of(context)!.close_button_label),
          ),
        ],
      ),
    );
  }

  Future<void> _loadEpisodeDetails() async {
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
        // No server connection: still show the episode we were given (e.g. a
        // local download opened while offline) rather than an error page.
        setState(() {
          _isLoading = false;
        });
        return;
      }

      _castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
      GlobalServices.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
      final userId = settings.castawayUserId!;

      // People load on their own: they're a quick database read, while the
      // metadata can wait on the server.
      unawaited(_loadPeople(userId));

      final episodeDetails = await _castawayService.getEpisodeMetadata(
        _episode!.episodeId,
        userId,
        isYoutube: _episode!.isYoutube,
        personEpisode: false, // Adjust if needed
      );

      if (episodeDetails != null) {
        setState(() {
          _episode = episodeDetails;
          _isLoading = false;
        });
        _resolveArtColor();
      } else {
        // Metadata unavailable: fall back to the episode passed in so the page
        // (and playback of a local download) still works.
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // Likely offline. Keep the initial episode so local downloads remain
      // playable; only surface an error if we have nothing to show.
      setState(() {
        if (_episode == null) {
          _errorMessage = L.of(context)!.error_loading_episode_details(e.toString());
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPeople(int userId) async {
    final episode = _episode;
    if (episode == null || episode.episodeId <= 0 || episode.isYoutube) return;
    try {
      final people = await _castawayService.getEpisodePeople(episode.episodeId);
      if (people != null) {
        if (mounted) {
          setState(() => _people = people);
        }
        return;
      }
      // Servers before the people endpoints: read-only, from the 2.0 data.
      final data = await _castawayService.fetchPodcasting2Data(episode.episodeId, userId);
      final legacy = (data?['people'] as List<dynamic>? ?? const [])
          .map((e) => CreditedPerson.fromJson(e as Map<String, dynamic>))
          .where((p) => p.name.isNotEmpty && p.name != 'Unknown Host')
          .toList();
      if (mounted) setState(() => _people = legacy);
    } catch (e) {
      debugPrint('Error loading episode people: $e');
    }
  }

  bool _isCurrentEpisodePlaying() {
    try {
      final audioPlayerService = Provider.of<AudioPlayerService>(context, listen: false);
      final currentEpisode = audioPlayerService.nowPlaying;
      return currentEpisode != null && currentEpisode.guid == _episode!.episodeUrl;
    } catch (e) {
      return false;
    }
  }

  bool _isAudioPlaying() {
    try {
      final audioPlayerService = Provider.of<AudioPlayerService>(context, listen: false);
      // This method is no longer needed since we're using StreamBuilder
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _togglePlayPause() async {
    
    if (_audioService == null) {
      _showSnackBar(L.of(context)!.audio_service_not_available, Colors.red);
      return;
    }

    try {
      final audioPlayerService = Provider.of<AudioPlayerService>(context, listen: false);
      
      // Check if this episode is currently playing
      if (_isCurrentEpisodePlaying()) {
        // This episode is loaded, check current state and toggle
        final currentState = audioPlayerService.playingState;
        if (currentState != null) {
          // Listen to the current state
          final state = await currentState.first;
          if (state == AudioState.playing) {
            await audioPlayerService.pause();
          } else {
            await audioPlayerService.play();
          }
        } else {
          await audioPlayerService.play();
        }
      } else {
        // Start playing this episode. Show loading feedback until the audio
        // system acknowledges it (cleared by the episodeEvent subscription).
        setState(() => _isStartingPlayback = true);
        await playCastawayEpisodeWithOptionalFullScreen(
          context,
          _audioService!,
          _episode!,
          resume: _episode!.isStarted,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStartingPlayback = false);
      }
      _showSnackBar(L.current.failed_to_control_playback(e.toString()), Colors.red);
    }
  }

  Future<void> _handleTimestampTap(Duration timestamp) async {
    
    if (_audioService == null) {
      _showSnackBar(L.of(context)!.audio_service_not_available, Colors.red);
      return;
    }

    try {
      final audioPlayerService = Provider.of<AudioPlayerService>(context, listen: false);
      
      // Check if this episode is currently playing
      final currentEpisode = audioPlayerService.nowPlaying;
      final isCurrentEpisode = currentEpisode != null && 
          currentEpisode.guid == _episode!.episodeUrl;
      
      if (!isCurrentEpisode) {
        // Start playing the episode first
        await playCastawayEpisodeWithOptionalFullScreen(
          context,
          _audioService!,
          _episode!,
          resume: false, // Start from beginning initially
        );
        
        // Wait a moment for the episode to start loading
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Seek to the timestamp (convert Duration to seconds as int)
      await audioPlayerService.seek(position: timestamp.inSeconds);
      
    } catch (e) {
      _showSnackBar(L.current.failed_to_jump_to_timestamp(e.toString()), Colors.red);
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(1, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _saveEpisode() async {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    try {
      final success = await _castawayService.saveEpisode(
        _episode!.episodeId,
        userId,
        _episode!.isYoutube,
      );

      if (success) {
        setState(() {
          _episode = _updateEpisodeProperty(_episode!, saved: true);
        });
        _showSnackBar(L.current.episode_saved, Colors.green);
      } else {
        _showSnackBar(L.current.failed_to_save_episode, Colors.red);
      }
    } catch (e) {
      if (await _enqueueOffline(PendingActionType.saveEpisode, userId)) {
        setState(() => _episode = _updateEpisodeProperty(_episode!, saved: true));
        _showSnackBar(L.current.saved_sync_when_online, Colors.blueGrey);
      } else {
        _showSnackBar(L.current.error_saving_episode(e.toString()), Colors.red);
      }
    }
  }

  Future<void> _removeSavedEpisode() async {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    try {
      final success = await _castawayService.removeSavedEpisode(
        _episode!.episodeId,
        userId,
        _episode!.isYoutube,
      );

      if (success) {
        setState(() {
          _episode = _updateEpisodeProperty(_episode!, saved: false);
        });
        _showSnackBar(L.current.removed_from_saved_episodes, Colors.orange);
      } else {
        _showSnackBar(L.current.failed_to_remove_saved_episode, Colors.red);
      }
    } catch (e) {
      if (await _enqueueOffline(PendingActionType.removeSaved, userId)) {
        setState(() => _episode = _updateEpisodeProperty(_episode!, saved: false));
        _showSnackBar(L.current.removed_sync_when_online, Colors.blueGrey);
      } else {
        _showSnackBar(L.current.error_removing_saved_episode(e.toString()), Colors.red);
      }
    }
  }

  Future<void> _toggleQueue() async {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    try {
      bool success;
      if (_episode!.queued) {
        success = await _castawayService.removeQueuedEpisode(
          _episode!.episodeId,
          userId,
          _episode!.isYoutube,
        );
        if (success) {
          setState(() {
            _episode = _updateEpisodeProperty(_episode!, queued: false);
          });
          _showSnackBar(L.current.removed_from_queue, Colors.orange);
        }
      } else {
        success = await _castawayService.queueEpisode(
          _episode!.episodeId,
          userId,
          _episode!.isYoutube,
        );
        if (success) {
          setState(() {
            _episode = _updateEpisodeProperty(_episode!, queued: true);
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
  }

  Future<void> _toggleDownload() async {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    try {
      bool success;
      if (_episode!.downloaded) {
        success = await _castawayService.deleteEpisode(
          _episode!.episodeId,
          userId,
          _episode!.isYoutube,
        );
        if (success) {
          setState(() {
            _episode = _updateEpisodeProperty(_episode!, downloaded: false);
          });
          _showSnackBar(L.current.episode_deleted_from_server, Colors.orange);
        }
      } else {
        success = await _castawayService.downloadEpisode(
          _episode!.episodeId,
          userId,
          _episode!.isYoutube,
        );
        if (success) {
          setState(() {
            _episode = _updateEpisodeProperty(_episode!, downloaded: true);
          });
          _showSnackBar(L.current.episode_download_queued, Colors.green);
        }
      }

      if (!success) {
        _showSnackBar(L.current.failed_to_update_download, Colors.red);
      }
    } catch (e) {
      _showSnackBar(L.current.error_updating_download(e.toString()), Colors.red);
    }
  }

  Future<void> _toggleComplete() async {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null) {
      _showSnackBar(L.of(context)!.not_logged_in, Colors.red);
      return;
    }

    try {
      bool success;
      if (_episode!.completed) {
        success = await _castawayService.markEpisodeUncompleted(
          _episode!.episodeId,
          userId,
          _episode!.isYoutube,
        );
        if (success) {
          setState(() {
            _episode = _updateEpisodeProperty(_episode!, completed: false);
          });
          _showSnackBar(L.current.marked_as_incomplete, Colors.orange);
        }
      } else {
        success = await _castawayService.markEpisodeCompleted(
          _episode!.episodeId,
          userId,
          _episode!.isYoutube,
        );
        if (success) {
          setState(() {
            _episode = _updateEpisodeProperty(_episode!, completed: true);
          });
          _showSnackBar(L.current.marked_as_complete, Colors.green);
        }
      }

      if (!success) {
        _showSnackBar(L.current.failed_to_update_completion, Colors.red);
      }
    } catch (e) {
      final wasCompleted = _episode!.completed;
      final type = wasCompleted ? PendingActionType.markUncompleted : PendingActionType.markCompleted;
      if (await _enqueueOffline(type, userId)) {
        setState(() => _episode = _updateEpisodeProperty(_episode!, completed: !wasCompleted));
        _showSnackBar(
          wasCompleted ? L.current.marked_incomplete_sync_when_online : L.current.marked_complete_sync_when_online,
          Colors.blueGrey,
        );
      } else {
        _showSnackBar(L.current.error_updating_completion(e.toString()), Colors.red);
      }
    }
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
      podcastId: episode.podcastId,
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

  Future<void> _navigateToPodcast() async {
    if (_episode!.podcastId == null) {
      _showSnackBar(L.of(context)!.podcast_id_not_available, Colors.orange);
      return;
    }

    await navigateToPodcastById(
      context,
      _episode!.podcastId!,
      fallbackTitle: _episode!.podcastName,
      fallbackArtwork: _episode!.episodeArtwork,
    );
  }

  @override
  Widget build(BuildContext context) {
    // No loading screen: the episode we were handed renders immediately and
    // the full metadata fills in when it arrives.
    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L.of(context)!.episode_details_title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  PhosphorIconsRegular.warningCircle,
                  color: Theme.of(context).colorScheme.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadEpisodeDetails,
                  child: Text(L.of(context)!.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    // Eases the header between colours when fuller artwork arrives.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _accentColor(theme)),
      duration: const Duration(milliseconds: 350),
      builder: (context, accent, _) => _buildPage(theme, accent!),
    );
  }

  Widget _buildPage(ThemeData theme, Color accent) {
    final bg = theme.scaffoldBackgroundColor;
    final headerTint = Color.alphaBlend(accent.withOpacity(0.18), bg);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: headerTint,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: L.of(context)!.share,
            icon: const Icon(PhosphorIconsRegular.shareNetwork),
            onPressed: _shareEpisode,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(theme, accent, headerTint, bg),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPlayButton(accent),
                          const SizedBox(height: 12),
                          _buildActionStrip(theme, accent),
                          if (_people.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            PeopleStrip(title: L.of(context)!.in_this_episode, people: _people),
                          ],
                          const SizedBox(height: 24),
                          Text(
                            L.of(context)!.notes_label,
                            style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (_isLoading && _episode!.episodeDescription.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                ),
                              ),
                            )
                          else
                            EpisodeDescription(
                              content: _episode!.episodeDescription,
                              onTimestampTap: _handleTimestampTap,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Artwork-derived accent when that setting is on, else the theme's.
  Color _accentColor(ThemeData theme) {
    final enabled = Provider.of<SettingsBloc>(context, listen: false).currentSettings.artworkAccentColors;
    return (enabled ? _artColor : null) ?? theme.primaryColor;
  }

  void _resolveArtColor() {
    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
    if (!settings.artworkAccentColors || _episode == null) return;
    final brightness = ThemeData.estimateBrightnessForColor(Theme.of(context).scaffoldBackgroundColor);
    final url = _episode!.episodeArtwork;
    _artColor = ArtworkColors.cached(url, null, brightness);
    if (_artColor != null) return;
    ArtworkColors.resolve(url, null, brightness).then((color) {
      if (!mounted || color == null || url != _episode?.episodeArtwork) return;
      setState(() => _artColor = color);
    });
  }

  Widget _buildHeader(ThemeData theme, Color accent, Color headerTint, Color bg) {
    final muted = theme.hintColor;
    final meta = [
      _episode!.formattedPubDate,
      if (_episode!.episodeDuration > 0) humanDuration(_episode!.episodeDuration),
    ].join('  ·  ');

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [headerTint, bg],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: LazyNetworkImage(
                imageUrl: _episode!.episodeArtwork,
                width: 200,
                height: 200,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: _navigateToPodcast,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _episode!.podcastName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall!.copyWith(color: accent, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(PhosphorIconsBold.caretRight, size: 14, color: accent),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _episode!.episodeTitle,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold, height: 1.25),
            ),
            const SizedBox(height: 8),
            Text(meta, style: theme.textTheme.bodyMedium!.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton(Color accent) {
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black;

    return StreamBuilder<AudioState>(
      stream: Provider.of<AudioPlayerService>(context, listen: false).playingState,
      builder: (context, snapshot) {
        final isCurrentEpisode = _isCurrentEpisodePlaying();
        final state = snapshot.data;
        // Treat buffering/starting as active so the button reads correctly
        // through the whole start sequence.
        final isActive = isCurrentEpisode &&
            (state == AudioState.playing || state == AudioState.buffering || state == AudioState.starting);
        // Spinner while we've started this episode but the audio system
        // hasn't acknowledged it yet.
        final showSpinner = _isStartingPlayback && !isCurrentEpisode;
        final started = _episode!.isStarted && !_episode!.completed;

        final IconData icon;
        final String label;
        if (isActive) {
          icon = PhosphorIconsFill.pause;
          label = L.of(context)!.pause;
        } else if (_episode!.completed) {
          icon = PhosphorIconsBold.arrowCounterClockwise;
          label = L.of(context)!.play_again;
        } else if (started) {
          icon = PhosphorIconsFill.play;
          final remaining = _episode!.episodeDuration - (_episode!.listenDuration ?? 0);
          label = L.of(context)!.resume_time_left(humanDuration(remaining));
        } else {
          icon = PhosphorIconsFill.play;
          label = L.of(context)!.play;
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: onAccent,
                    disabledBackgroundColor: accent.withOpacity(0.5),
                    disabledForegroundColor: onAccent.withOpacity(0.7),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _actionGuard.inProgress ? null : () => _runGuarded(_togglePlayPause),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: showSpinner
                        ? SizedBox(
                            key: const ValueKey('loading'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: onAccent),
                          )
                        : Row(
                            key: ValueKey(label),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 22),
                              const SizedBox(width: 8),
                              Text(label),
                            ],
                          ),
                  ),
                ),
              ),
              if (started)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: (_episode!.progressPercentage / 100).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: onAccent.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(onAccent.withOpacity(0.6)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionStrip(ThemeData theme, Color accent) {
    final busy = _actionGuard.inProgress;
    final e = _episode!;
    return Row(
      children: [
        _EpisodeAction(
          icon: e.saved ? PhosphorIconsFill.bookmarkSimple : PhosphorIconsRegular.bookmarkSimple,
          label: e.saved ? L.of(context)!.saved : L.of(context)!.save,
          active: e.saved,
          accent: accent,
          onTap: busy ? null : () => _runGuarded(e.saved ? _removeSavedEpisode : _saveEpisode),
        ),
        _EpisodeAction(
          icon: e.queued ? PhosphorIconsFill.queue : PhosphorIconsRegular.queue,
          label: e.queued ? L.of(context)!.queued : L.of(context)!.queue,
          active: e.queued,
          accent: accent,
          onTap: busy ? null : () => _runGuarded(_toggleQueue),
        ),
        _EpisodeAction(
          icon: _isDownloadedLocally ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.downloadSimple,
          label: _isDownloadedLocally ? L.of(context)!.on_device : L.of(context)!.download,
          active: _isDownloadedLocally,
          accent: accent,
          onTap: busy ? null : () => _runGuarded(_isDownloadedLocally ? _confirmDeleteLocalDownload : _localDownloadEpisode),
        ),
        _EpisodeAction(
          icon: e.completed ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.checkCircle,
          label: L.of(context)!.episode_filter_played_label,
          active: e.completed,
          accent: accent,
          onTap: busy ? null : () => _runGuarded(_toggleComplete),
        ),
        _EpisodeAction(
          icon: PhosphorIconsRegular.dotsThree,
          label: L.of(context)!.more_label,
          active: false,
          accent: accent,
          onTap: _showMoreSheet,
        ),
      ],
    );
  }

  Future<void> _confirmDeleteLocalDownload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.of(context)!.remove_download_title),
        content: Text(L.of(context)!.remove_download_description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(L.of(context)!.cancel_button_label)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(L.of(context)!.remove)),
        ],
      ),
    );
    if (confirmed == true) await _deleteLocalDownload();
  }

  void _showMoreSheet() {
    final e = _episode!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        void run(VoidCallback action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(e.downloaded ? PhosphorIconsRegular.cloudSlash : PhosphorIconsRegular.cloudArrowDown),
                title: Text(e.downloaded ? L.of(context)!.remove_server_download : L.of(context)!.download_to_server),
                subtitle: Text(L.of(context)!.stored_on_server),
                enabled: !_actionGuard.inProgress,
                onTap: () => run(() => _runGuarded(_toggleDownload)),
              ),
              if (e.episodeId > 0)
                ListTile(
                  leading: const Icon(PhosphorIconsRegular.folderPlus),
                  title: Text(L.of(context)!.add_to_collection),
                  onTap: () => run(() => showAddToCollectionSheet(context,
                      episodes: [(e.episodeId, e.isYoutube)])),
                ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.microphoneStage),
                title: Text(L.of(context)!.go_to_podcast),
                onTap: () => run(_navigateToPodcast),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.shareNetwork),
                title: Text(L.of(context)!.share_episode),
                onTap: () => run(_shareEpisode),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _episodeSub?.cancel();
    _stateSub?.cancel();
    // Don't dispose global audio service - it should persist across pages
    super.dispose();
  }
}

/// Icon-over-label action used in the episode page's action strip.
class _EpisodeAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback? onTap;

  const _EpisodeAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = active ? accent : softNeutral(theme).withOpacity(0.8);
    final color = onTap == null ? base.withOpacity(0.4) : base;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
