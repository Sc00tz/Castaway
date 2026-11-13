// CarPlay list items are plain Episodes; playback rebuilds the Castaway episode
// from them so it goes through the tracked play path. The server-download and
// YouTube flags decide the stream URL, so they must survive the round trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/services/carplay/carplay_service.dart';

import '../../support/factories.dart';

void main() {
  test('rebuilds id, position and source URL from a CarPlay item', () {
    final ep = CarPlayService.toCastawayEpisode(buildEpisode(
      guid: 'castaway_101',
      contentUrl: 'https://example.com/episode.mp3',
    )
      ..link = 'https://example.com/episode.mp3'
      ..position = 754000
      ..duration = 600000);

    expect(ep, isNotNull);
    expect(ep!.episodeId, 101);
    expect(ep.listenDuration, 754);
    expect(ep.episodeDuration, 600);
    expect(ep.episodeUrl, 'https://example.com/episode.mp3');
    expect(ep.downloaded, isFalse);
    expect(ep.isYoutube, isFalse);
  });

  test('recovers server-download and YouTube flags from the stream URL', () {
    final downloaded = CarPlayService.toCastawayEpisode(buildEpisode(
      guid: 'castaway_5',
      contentUrl: 'https://pp.example/api/data/stream/5?api_key=k&user_id=1',
    ));
    final youtube = CarPlayService.toCastawayEpisode(buildEpisode(
      guid: 'castaway_6',
      contentUrl: 'https://pp.example/api/data/stream/6?api_key=k&user_id=1&type=youtube',
    ));

    expect(downloaded!.downloaded, isTrue);
    expect(downloaded.isYoutube, isFalse);
    expect(youtube!.isYoutube, isTrue);
    expect(youtube.downloaded, isFalse);
  });

  test('items without a Castaway id are left to the direct play path', () {
    expect(CarPlayService.toCastawayEpisode(buildEpisode(guid: 'https://feed/ep')), isNull);
    expect(CarPlayService.toCastawayEpisode(buildEpisode(guid: 'castaway_x')), isNull);
  });

  test('Up Next is the server queue minus the playing and finished episodes', () {
    final queue = [
      buildCastawayEpisode(episodeId: 1),
      buildCastawayEpisode(episodeId: 2),
      buildCastawayEpisode(episodeId: 3, completed: true),
      buildCastawayEpisode(episodeId: 4),
      buildCastawayEpisode(episodeId: 5),
    ];

    expect(CarPlayService.upNextFrom(queue, playingEpisodeId: 2).map((e) => e.episodeId), [1, 4, 5]);
    expect(CarPlayService.upNextFrom(queue, playingEpisodeId: 2, limit: 2).map((e) => e.episodeId), [1, 4]);
    expect(CarPlayService.upNextFrom(queue).map((e) => e.episodeId), [1, 2, 4, 5]);
  });
}
