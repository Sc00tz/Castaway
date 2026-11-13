// lib/ui/utils/position_utils.dart
import 'package:flutter/material.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/services/global_services.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';

/// Which position episode lists show.
///
/// The server keeps the most recently recorded position for every episode, so
/// its value is right unless this device has progress the server hasn't
/// received yet. That progress waits in the offline outbox, and is overlaid
/// here. Every list (Home, Feed, History, Queue, Saved) uses the same rule, so
/// they always agree.
///
/// (This used to show the *furthest* of the server's position and the phone's
/// local player database. That kept stale positions alive and hid rewinds, and
/// Home didn't apply it at all, so screens disagreed.)
class PositionUtils {
  /// Generate consistent GUID for Castaway episodes
  static String generateEpisodeGuid(CastawayEpisode episode) {
    return 'castaway_${episode.episodeId}';
  }

  /// [episodes] with this device's unsynced progress overlaid on the server's
  /// positions. The signature is kept for existing callers; the context,
  /// service and user aren't needed any more.
  static Future<List<CastawayEpisode>> enrichEpisodesWithBestPositions(
    BuildContext context,
    CastawayService castawayService,
    List<CastawayEpisode> episodes,
    int userId,
  ) =>
      withPendingPositions(episodes);

  /// [episodes] with the outbox's unsent positions overlaid.
  static Future<List<CastawayEpisode>> withPendingPositions(
    List<CastawayEpisode> episodes, {
    OfflineActionQueue? queue,
  }) async {
    final outbox = queue ?? GlobalServices.offlineActionQueue;
    if (outbox == null || episodes.isEmpty) return episodes;
    return overlay(episodes, await outbox.pendingPositions());
  }

  /// [episodes] with [positions] (keyed by [PositionUpdate.keyFor]) replacing
  /// their positions. Returns the same list when nothing changes.
  static List<CastawayEpisode> overlay(List<CastawayEpisode> episodes, Map<String, double> positions) {
    if (positions.isEmpty) return episodes;
    var changed = false;
    final result = episodes.map((episode) {
      final seconds = positions[PositionUpdate.keyFor(episode.episodeId, episode.isYoutube)];
      if (seconds == null || seconds.round() == episode.listenDuration) return episode;
      changed = true;
      return episode.withListenDuration(seconds.round());
    }).toList();
    return changed ? result : episodes;
  }

  /// [episodes] with one live [update] applied (see
  /// [OfflineActionQueue.positionUpdates]). Returns the same list when [update]
  /// isn't for any of them.
  static List<CastawayEpisode> applyUpdate(List<CastawayEpisode> episodes, PositionUpdate update) {
    return overlay(episodes, {update.key: update.seconds});
  }
}
