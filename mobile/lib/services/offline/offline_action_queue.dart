// lib/services/offline/offline_action_queue.dart

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';
import 'package:castaway_mobile/entities/pending_action.dart';
import 'package:castaway_mobile/repository/repository.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/settings/settings_service.dart';

/// Durable "outbox" for episode interactions (progress, completion, save,
/// queue, history). Every interaction for a locally-playable episode is written
/// here and flushed to the Castaway server when the device is online — on
/// app start, on reconnect, and opportunistically after each enqueue.
///
/// This is what lets users listen to downloaded episodes offline and have their
/// progress / completion / saved state reconcile with the server once back
/// online, rather than being silently dropped.
class OfflineActionQueue {
  final log = Logger('OfflineActionQueue');

  final Repository repository;
  final CastawayService castawayService;
  final SettingsService settingsService;

  /// Drop an item after the server has refused it this many times. Only
  /// refusals count: while the server can't be reached at all (offline, server
  /// down) items wait indefinitely, so offline listening is never lost.
  static const int _maxRetries = 8;

  bool _flushing = false;
  bool _flushRequested = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  final StreamController<PositionUpdate> _positionUpdates = StreamController<PositionUpdate>.broadcast();

  /// Every position this device records, as it's recorded. Episode lists listen
  /// so the progress they show follows playback without reloading.
  Stream<PositionUpdate> get positionUpdates => _positionUpdates.stream;

  OfflineActionQueue({
    required this.repository,
    required this.castawayService,
    required this.settingsService,
  });

  /// Begin listening for connectivity changes and attempt an initial flush.
  void start() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        log.fine('Connectivity restored - flushing offline action queue');
        flush();
      }
    });

    // Drain anything left over from a previous session.
    flush();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _positionUpdates.close();
  }

  /// Persist an interaction and immediately attempt to flush it.
  ///
  /// For [PendingActionType.recordPosition] only the latest position per episode
  /// matters, so any earlier pending position update for the same episode is
  /// collapsed to avoid the queue growing without bound during playback.
  Future<void> enqueue(PendingAction action) async {
    try {
      if (action.type == PendingActionType.recordPosition) {
        final existing = await repository.getPendingActions();
        for (final a in existing) {
          if (a.type == PendingActionType.recordPosition &&
              a.episodeId == action.episodeId &&
              a.isYoutube == action.isYoutube &&
              a.id != null) {
            await repository.deletePendingAction(a.id!);
          }
        }
      }

      await repository.savePendingAction(action);
      final position = action.position;
      if (action.type == PendingActionType.recordPosition && position != null && !_positionUpdates.isClosed) {
        _positionUpdates.add(PositionUpdate(action.episodeId, action.isYoutube, position));
      }
    } catch (e) {
      log.warning('Failed to enqueue offline action: $e');
      return;
    }

    // Opportunistic flush — succeeds immediately when online, harmless offline.
    flush();
  }

  /// Convenience helpers for the common interactions.
  Future<void> enqueuePosition(int episodeId, int userId, double positionSeconds, bool isYoutube) =>
      enqueue(PendingAction(
        type: PendingActionType.recordPosition,
        episodeId: episodeId,
        userId: userId,
        isYoutube: isYoutube,
        payload: {'position': positionSeconds},
      ));

  Future<void> enqueueHistory(int episodeId, int userId, double positionSeconds, bool isYoutube) =>
      enqueue(PendingAction(
        type: PendingActionType.addHistory,
        episodeId: episodeId,
        userId: userId,
        isYoutube: isYoutube,
        payload: {'position': positionSeconds},
      ));

  Future<void> enqueueSimple(PendingActionType type, int episodeId, int userId, bool isYoutube) =>
      enqueue(PendingAction(type: type, episodeId: episodeId, userId: userId, isYoutube: isYoutube));

  /// The most recent position (seconds) recorded for an episode that has not
  /// reached the server yet, or null when nothing is pending. Resume uses this
  /// so progress made while offline isn't lost to the server's stale value.
  Future<double?> pendingPosition(int episodeId, bool isYoutube) async {
    try {
      final actions = await repository.getPendingActions();
      double? latest;
      // Oldest first, so the last match is the newest.
      for (final a in actions) {
        if (a.type == PendingActionType.recordPosition &&
            a.episodeId == episodeId &&
            a.isYoutube == isYoutube &&
            a.position != null) {
          latest = a.position;
        }
      }
      return latest;
    } catch (e) {
      log.warning('Failed to read pending position: $e');
      return null;
    }
  }

  /// The newest unsent position (seconds) of every episode that has one, keyed
  /// by [PositionUpdate.keyFor]. Lists overlay these on the server's values:
  /// they're this device's latest progress, newer than what the server has.
  Future<Map<String, double>> pendingPositions() async {
    try {
      final positions = <String, double>{};
      // Oldest first, so later entries overwrite earlier ones.
      for (final a in await repository.getPendingActions()) {
        final p = a.position;
        if (a.type == PendingActionType.recordPosition && p != null) {
          positions[PositionUpdate.keyFor(a.episodeId, a.isYoutube)] = p;
        }
      }
      return positions;
    } catch (e) {
      log.warning('Failed to read pending positions: $e');
      return {};
    }
  }

  /// Send all pending actions to the server in order.
  ///
  /// When an item fails, a quick reachability check decides what that means:
  /// - server unreachable (offline, down): stop; everything waits for the next
  ///   trigger, and no retries are used up;
  /// - server reachable: it refused this item, which counts toward
  ///   [_maxRetries]; the rest of the queue carries on.
  ///
  /// A flush requested while one is running (e.g. a new position saved
  /// mid-flush) runs again straight after, so the newest item isn't left
  /// waiting for the next trigger.
  Future<void> flush() async {
    if (_flushing) {
      _flushRequested = true;
      return;
    }

    final server = settingsService.castawayServer;
    final apiKey = settingsService.castawayApiKey;
    if (server == null || apiKey == null) {
      // Not logged in / no credentials — nothing we can send yet.
      return;
    }

    _flushing = true;
    try {
      castawayService.setCredentials(server, apiKey);
      do {
        _flushRequested = false;
        if (!await _drain(server)) break; // unreachable: wait for the next trigger
      } while (_flushRequested);
    } finally {
      _flushing = false;
    }
  }

  /// One pass over the queue. Returns false if it stopped because the server
  /// couldn't be reached.
  Future<bool> _drain(String server) async {
    for (final action in await repository.getPendingActions()) {
      try {
        await _dispatch(action);
        if (action.id != null) {
          await repository.deletePendingAction(action.id!);
        }
      } catch (e) {
        if (!await castawayService.verifyCastawayInstance(server)) {
          log.fine('Server unreachable - keeping ${action.type.name} queued: $e');
          return false;
        }
        log.warning('Server refused pending action (${action.type.name}): $e');
        action.retryCount++;
        if (action.id == null) continue;
        if (action.retryCount < _maxRetries) {
          await repository.savePendingAction(action);
        } else {
          log.warning('Dropping pending action after $_maxRetries refusals: ${action.type.name}');
          await repository.deletePendingAction(action.id!);
        }
      }
    }
    return true;
  }

  /// Send one action. Throws if it didn't go through: the service methods
  /// report failure by returning false, and treating that as success is how
  /// progress used to be silently lost.
  Future<void> _dispatch(PendingAction a) async {
    final bool sent;
    switch (a.type) {
      case PendingActionType.recordPosition:
        // Sent with the time the position was taken, so a late upload can't
        // overwrite newer progress made since (on any device).
        sent = await castawayService.recordListenDuration(
          a.episodeId,
          a.userId,
          a.position ?? 0,
          a.isYoutube,
          recordedAt: a.createdAt,
        );
      case PendingActionType.addHistory:
        sent = await castawayService.addHistory(a.episodeId, a.position ?? 0, a.userId, a.isYoutube);
      case PendingActionType.markCompleted:
        sent = await castawayService.markEpisodeCompleted(a.episodeId, a.userId, a.isYoutube);
      case PendingActionType.markUncompleted:
        sent = await castawayService.markEpisodeUncompleted(a.episodeId, a.userId, a.isYoutube);
      case PendingActionType.saveEpisode:
        sent = await castawayService.saveEpisode(a.episodeId, a.userId, a.isYoutube);
      case PendingActionType.removeSaved:
        sent = await castawayService.removeSavedEpisode(a.episodeId, a.userId, a.isYoutube);
      case PendingActionType.queue:
        sent = await castawayService.queueEpisode(a.episodeId, a.userId, a.isYoutube);
    }
    if (!sent) {
      throw StateError('${a.type.name} for episode ${a.episodeId} was not accepted');
    }
  }
}

/// A position this device recorded for an episode.
class PositionUpdate {
  final int episodeId;
  final bool isYoutube;
  final double seconds;

  const PositionUpdate(this.episodeId, this.isYoutube, this.seconds);

  /// Map key for an episode's position; podcast episodes and YouTube videos
  /// have separate id spaces.
  static String keyFor(int episodeId, bool isYoutube) => '${isYoutube ? 'yt' : 'ep'}:$episodeId';

  String get key => keyFor(episodeId, isYoutube);
}
