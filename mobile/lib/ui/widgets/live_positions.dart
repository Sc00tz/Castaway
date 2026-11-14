// lib/ui/widgets/live_positions.dart
//
// Keeps an episode list's progress bars moving while an episode plays. Every
// position this phone records (the 15-second save, a skip or scrub, pausing)
// comes through the outbox's position stream; a screen mixes this in and
// applies each one to the episodes it shows.

import 'dart:async';

import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/services/global_services.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';
import 'package:castaway_mobile/ui/utils/position_utils.dart';
import 'package:flutter/widgets.dart';

mixin LivePositions<T extends StatefulWidget> on State<T> {
  StreamSubscription<PositionUpdate>? _livePositionSub;

  /// Positions recorded since this screen opened, keyed by [PositionUpdate.keyFor].
  final Map<String, double> _livePositions = {};

  /// Where positions come from; tests replace it.
  @visibleForTesting
  Stream<PositionUpdate>? get livePositionStream => GlobalServices.offlineActionQueue?.positionUpdates;

  /// Apply [update] to this screen's lists. Return true when anything shown
  /// changed; the screen is then rebuilt.
  bool applyLivePosition(PositionUpdate update);

  /// [episodes] with the positions recorded since this screen opened. Use on
  /// freshly loaded pages so a load that started before a save can't put an
  /// older position back.
  List<CastawayEpisode> withLivePositions(List<CastawayEpisode> episodes) =>
      PositionUtils.overlay(episodes, _livePositions);

  /// The live position for one episode, if one was recorded since this screen opened.
  double? livePositionFor(int episodeId, bool isYoutube) =>
      _livePositions[PositionUpdate.keyFor(episodeId, isYoutube)];

  @override
  void initState() {
    super.initState();
    _livePositionSub = livePositionStream?.listen((update) {
      if (!mounted) return;
      _livePositions[update.key] = update.seconds;
      if (applyLivePosition(update)) setState(() {});
    });
  }

  @override
  void dispose() {
    _livePositionSub?.cancel();
    super.dispose();
  }
}
