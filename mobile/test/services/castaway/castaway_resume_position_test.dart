// Regression tests for where playback resumes. The newest known position wins,
// not the furthest: this device's unsynced progress in the outbox, else the
// server's position, else the (possibly stale) data the screen handed over.
// That makes skipping back or restarting on another device stick. A start
// position that came only from stale screen data must not be recorded, or it
// would overwrite newer progress made elsewhere.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/app_settings.dart';
import 'package:castaway_mobile/entities/episode.dart';
import 'package:castaway_mobile/repository/sembast/sembast_repository.dart';
import 'package:castaway_mobile/services/audio/audio_player_service.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';
import 'package:castaway_mobile/services/castaway/castaway_audio_service.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/settings/settings_service.dart';

import '../../support/factories.dart';
import '../../support/fakes.dart';
import '../../support/in_memory_repository.dart';

class MockCastawayService extends Mock implements CastawayService {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

// castawayServer stays null, so the outbox never tries to send: everything
// enqueued remains pending and observable.
class MockSettingsService extends Mock implements SettingsService {}

void main() {
  late MockAudioPlayerService audio;
  late MockCastawayService api;
  late SembastRepository repository;
  late OfflineActionQueue queue;
  late CastawayAudioService service;

  setUpAll(registerCommonFallbacks);

  setUp(() {
    audio = MockAudioPlayerService();
    api = MockCastawayService();
    final settingsBloc = MockSettingsBloc();
    repository = newInMemoryRepository();
    queue = OfflineActionQueue(
      repository: repository,
      castawayService: api,
      settingsService: MockSettingsService(),
    );
    service = CastawayAudioService(audio, api, settingsBloc)..setActionQueue(queue);
    addTearDown(service.dispose);

    when(() => settingsBloc.currentSettings)
        .thenReturn(AppSettings.sensibleDefaults().copyWith(castawayUserId: 42));
    when(() => audio.findDownloadedEpisode(any())).thenAnswer((_) async => null);
    when(() => audio.playEpisode(
          episode: any(named: 'episode'),
          resume: any(named: 'resume'),
          playbackSpeed: any(named: 'playbackSpeed'),
        ))
        .thenAnswer((_) async {});
    when(() => audio.setPlaybackSpeed(any())).thenAnswer((_) async {});
    when(() => api.getPodcastIdFromEpisode(any(), any(), any())).thenAnswer((_) async => 7);
    when(() => api.fetchPodcasting2Data(any(), any())).thenAnswer((_) async => null);
    when(() => api.getPlayEpisodeDetails(any(), any(), any())).thenAnswer(
      (_) async => PlayEpisodeDetails(playbackSpeed: 1.0, startSkip: 0, endSkip: 0),
    );
  });

  void serverPosition(int? seconds) {
    when(() => api.getEpisodeMetadata(any(), any(), isYoutube: any(named: 'isYoutube')))
        .thenAnswer((_) async => buildCastawayEpisode(listenDuration: seconds));
  }

  Episode playedEpisode() => verify(
        () => audio.playEpisode(
          episode: captureAny(named: 'episode'),
          resume: true,
          playbackSpeed: any(named: 'playbackSpeed'),
        ),
      ).captured.single as Episode;

  test('resumes from the server when the list data is stale', () async {
    serverPosition(300);

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(listenDuration: 100));

    expect(playedEpisode().position, 300000);
    expect(await queue.pendingPosition(101, false), 300);
  });

  test('resumes from unsynced offline progress and keeps it in the outbox', () async {
    serverPosition(100);
    await queue.enqueuePosition(101, 42, 900, false);

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(listenDuration: 100));

    expect(playedEpisode().position, 900000);
    expect(await queue.pendingPosition(101, false), 900);
  });

  test('local download resumes from unsynced offline progress', () async {
    when(() => audio.findDownloadedEpisode(any())).thenAnswer(
      (_) async => buildEpisode()..filepath = '/tmp',
    );
    await queue.enqueuePosition(101, 42, 900, false);

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(listenDuration: 100));

    expect(playedEpisode().position, 900000);
    expect(await queue.pendingPosition(101, false), 900);
  });

  test('a downloaded episode asks the server where to resume', () async {
    when(() => audio.findDownloadedEpisode(any())).thenAnswer(
      (_) async => buildEpisode()..filepath = '/tmp',
    );
    serverPosition(300);

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(listenDuration: 100));

    expect(playedEpisode().position, 300000);
  });

  test('skipping back on another device sticks: the newer, earlier position wins', () async {
    // The screen loaded 10:00, then another device rewound to 2:00.
    serverPosition(120);

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(listenDuration: 600));

    expect(playedEpisode().position, 120000);
    expect(await queue.pendingPosition(101, false), 120);
  });

  test('a start from stale screen data is played but not recorded', () async {
    // Server unreachable: only the screen's data is known, and it may be old.
    when(() => api.getEpisodeMetadata(any(), any(), isYoutube: any(named: 'isYoutube')))
        .thenThrow(Exception('offline'));

    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(listenDuration: 400));

    expect(playedEpisode().position, 400000);
    expect(await queue.pendingPosition(101, false), isNull,
        reason: 'recording it would overwrite newer progress made on another device');
  });

  test('completed episodes still start from the beginning', () async {
    serverPosition(500);
    await queue.enqueuePosition(101, 42, 900, false);

    await service.playCastawayEpisode(
      castawayEpisode: buildCastawayEpisode(listenDuration: 600, completed: true),
    );

    expect(playedEpisode().position, 0);
  });

  test('pendingPosition ignores other episodes and YouTube ids', () async {
    await queue.enqueuePosition(101, 42, 50, true);
    await queue.enqueuePosition(202, 42, 70, false);

    expect(await queue.pendingPosition(101, false), isNull);
    expect(await queue.pendingPosition(101, true), 50);
  });
}
