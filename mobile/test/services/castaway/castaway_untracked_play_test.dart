// Episodes from an unfollowed podcast's feed have no server id (#965). They
// must still play, straight from the feed URL, without any server tracking.

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
    when(() => audio.playEpisode(
          episode: any(named: 'episode'),
          resume: any(named: 'resume'),
          playbackSpeed: any(named: 'playbackSpeed'),
        ))
        .thenAnswer((_) async {});
    when(() => audio.applyEpisodeSkipSegments(
          silenceEnabled: any(named: 'silenceEnabled'),
          silenceRanges: any(named: 'silenceRanges'),
        )).thenAnswer((_) async {});
  });

  test('plays a feed episode with no server id from its URL, untracked', () async {
    await service.playCastawayEpisode(castawayEpisode: buildCastawayEpisode(episodeId: 0));

    final played = verify(
      () => audio.playEpisode(
        episode: captureAny(named: 'episode'),
        resume: false,
        playbackSpeed: any(named: 'playbackSpeed'),
      ),
    ).captured.single as Episode;
    expect(played.contentUrl, 'https://example.com/episode.mp3');
    expect(service.currentEpisodeId, isNull);
    verifyZeroInteractions(api);
  });
}
