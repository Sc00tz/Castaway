// How a streamed start waits on the server. Only the resume position and the
// playback settings may hold up the start, both for at most
// CastawayAudioService.startWait; chapters and people arrive afterwards.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/app_settings.dart';
import 'package:castaway_mobile/entities/episode.dart';
import 'package:castaway_mobile/services/castaway/castaway_audio_service.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';

import '../../support/factories.dart';
import '../../support/fakes.dart';

class MockCastawayService extends Mock implements CastawayService {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  late MockAudioPlayerService audio;
  late MockCastawayService api;
  late CastawayAudioService service;

  setUpAll(registerCommonFallbacks);

  setUp(() {
    audio = MockAudioPlayerService();
    api = MockCastawayService();
    final settingsBloc = MockSettingsBloc();
    service = CastawayAudioService(audio, api, settingsBloc);
    addTearDown(service.dispose);

    when(() => settingsBloc.currentSettings)
        .thenReturn(AppSettings.sensibleDefaults().copyWith(castawayUserId: 42));
    when(() => audio.findDownloadedEpisode(any())).thenAnswer((_) async => null);
    when(() => audio.playEpisode(
          episode: any(named: 'episode'),
          resume: any(named: 'resume'),
          playbackSpeed: any(named: 'playbackSpeed'),
        )).thenAnswer((_) async {});
    when(() => api.getPodcastIdFromEpisode(any(), any(), any())).thenAnswer((_) async => 7);
    when(() => api.fetchPodcasting2Data(any(), any())).thenAnswer((_) async => null);
    when(() => api.getPlayEpisodeDetails(any(), any(), any())).thenAnswer(
      (_) async => PlayEpisodeDetails(playbackSpeed: 1.0, startSkip: 0, endSkip: 0),
    );
    when(() => api.getEpisodeMetadata(any(), any(), isYoutube: any(named: 'isYoutube')))
        .thenAnswer((_) async => buildCastawayEpisode(listenDuration: 300));
  });

  ({Episode episode, bool resume, double? speed}) played() {
    final captured = verify(() => audio.playEpisode(
          episode: captureAny(named: 'episode'),
          resume: captureAny(named: 'resume'),
          playbackSpeed: captureAny(named: 'playbackSpeed'),
        )).captured;
    return (episode: captured[0] as Episode, resume: captured[1] as bool, speed: captured[2] as double?);
  }

  test('a slow server position starts from the known position after the wait', () async {
    when(() => api.getEpisodeMetadata(any(), any(), isYoutube: any(named: 'isYoutube')))
        .thenAnswer((_) => Completer<Never>().future);

    final watch = Stopwatch()..start();
    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(listenDuration: 100));

    expect(watch.elapsed, lessThan(CastawayAudioService.startWait * 2));
    expect(played().episode.position, 100000);
  });

  test('chapters and people do not hold up the start, and fill in once loaded', () async {
    final data = Completer<Map<String, dynamic>?>();
    when(() => api.fetchPodcasting2Data(any(), any())).thenAnswer((_) => data.future);

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode());
    final episode = played().episode;
    expect(episode.chapters, isEmpty);

    data.complete({
      'chapters': [
        {'title': 'Intro', 'startTime': 0},
        {'title': 'Main', 'startTime': 60},
      ],
    });
    await pumpEventQueue();

    final update = verify(() => audio.updateNowPlayingDetails(episode.guid, captureAny())).captured.single
        as void Function(Episode);
    update(episode);
    expect(episode.chapters.map((c) => c.title), ['Intro', 'Main']);
  });

  test('a per-podcast speed is passed to the start, the echoed default is not', () async {
    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode());
    expect(played().speed, isNull);

    when(() => api.getPlayEpisodeDetails(any(), any(), any())).thenAnswer(
      (_) async => PlayEpisodeDetails(playbackSpeed: 2.25, startSkip: 0, endSkip: 0, playbackSpeedCustomized: true),
    );
    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode());
    expect(played().speed, 2.25);
    verifyNever(() => audio.setPlaybackSpeed(any(), persist: any(named: 'persist')));
  });

  test('a fresh start begins past the intro instead of seeking after it plays', () async {
    when(() => api.getPlayEpisodeDetails(any(), any(), any())).thenAnswer(
      (_) async => PlayEpisodeDetails(playbackSpeed: 1.0, startSkip: 45, endSkip: 0),
    );

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(), resume: false);

    final start = played();
    expect(start.resume, isTrue);
    expect(start.episode.position, 45000);
    verifyNever(() => audio.seek(position: any(named: 'position')));
  });
}
