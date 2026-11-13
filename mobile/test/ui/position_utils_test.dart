// Every episode list shows the same position: the server's, unless this device
// has newer progress still waiting in the outbox. Home and the Feed used to
// apply different rules and disagree.

import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/home_data.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';
import 'package:castaway_mobile/ui/utils/position_utils.dart';

import '../support/factories.dart';

HomeEpisode homeEpisode(int id, int? seconds, {bool youtube = false}) => HomeEpisode(
      episodeId: id,
      podcastId: 1,
      episodeTitle: 'Episode $id',
      episodeDescription: '',
      episodeUrl: '',
      episodeArtwork: '',
      episodePubDate: '2026-01-01T00:00:00',
      episodeDuration: 3600,
      completed: false,
      podcastName: 'Show',
      isYoutube: youtube,
      listenDuration: seconds,
    );

HomeOverview overview(List<HomeEpisode> inProgress) => HomeOverview(
      recentEpisodes: inProgress,
      inProgressEpisodes: inProgress,
      queuePreview: const [],
      topPodcasts: const [],
      savedCount: 0,
      downloadedCount: 0,
      queueCount: 0,
      weeklyStats: WeeklyStats(),
    );

void main() {
  test('unsynced progress replaces the server position, including an earlier one', () {
    final episodes = [
      buildCastawayEpisode(episodeId: 1, listenDuration: 600),
      buildCastawayEpisode(episodeId: 2, listenDuration: 50),
    ];
    final shown = PositionUtils.overlay(episodes, {
      PositionUpdate.keyFor(1, false): 120, // skipped back on this phone, not synced yet
    });
    expect(shown.map((e) => e.listenDuration), [120, 50]);
  });

  test('nothing to apply returns the same list, so screens can skip a rebuild', () {
    final episodes = [buildCastawayEpisode(episodeId: 1, listenDuration: 600)];
    expect(identical(PositionUtils.overlay(episodes, {}), episodes), isTrue);
    expect(identical(PositionUtils.applyUpdate(episodes, const PositionUpdate(9, false, 5)), episodes), isTrue);
    expect(
      identical(PositionUtils.applyUpdate(episodes, const PositionUpdate(1, true, 5)), episodes),
      isTrue,
      reason: 'a YouTube video with the same id is a different episode',
    );
  });

  test('Home applies positions the same way', () {
    final data = overview([homeEpisode(1, 600), homeEpisode(2, 50)]);
    final shown = data.withPositions((id, youtube) => id == 1 && !youtube ? 1200 : null);
    expect(shown.inProgressEpisodes.map((e) => e.listenDuration), [1200, 50]);
    expect(shown.recentEpisodes.map((e) => e.listenDuration), [1200, 50]);
    expect(identical(data.withPositions((_, __) => null), data), isTrue);
  });
}
