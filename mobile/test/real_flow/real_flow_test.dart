// The phone's half of the real-flow test (tests/real-flow/run.sh): against the real server
// image, the app's own code signs in, finds a show on Apple (from recorded real answers),
// subscribes to it, and saves a listening position through the outbox, the way playback does.
// The web app then has to show that position.
//
// Without CASTAWAY_REAL_FLOW_SERVER the test is skipped.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';
import 'package:castaway_mobile/services/settings/settings_service.dart';

import '../support/in_memory_repository.dart';

final _env = Platform.environment;
final _server = _env['CASTAWAY_REAL_FLOW_SERVER'];
final _username = _env['CASTAWAY_REAL_FLOW_USERNAME'] ?? '';
final _password = _env['CASTAWAY_REAL_FLOW_PASSWORD'] ?? '';
final _out = _env['CASTAWAY_REAL_FLOW_OUT'];

/// The position the phone saves; the web app must show it.
const _position = 1234.0;

class _Settings extends Mock implements SettingsService {}

void main() {
  test('the phone signs in, finds a show on Apple, subscribes and saves a position', () async {
    final service = CastawayService(timeout: const Duration(seconds: 60));
    expect(await service.login(_server!, _username, _password), isTrue, reason: 'sign in');
    final userId = await service.getUserIdFromApiKey();
    expect(userId, isNotNull);

    final found = await service.searchPodcasts('99% Invisible', SearchProvider.itunes);
    final show = found.getUnifiedPodcasts().firstWhere((p) => p.title == '99% Invisible');
    expect(show.url, endsWith('/feeds/394775318.xml'), reason: 'the recorded Apple answer');

    expect(await service.addPodcast(show, userId!), isTrue, reason: 'subscribe');
    final subscribed = await service.getUserPodcasts(userId);
    // By title: the app's Podcast entity rewrites http:// feed addresses to https://.
    final podcast = subscribed.firstWhere(
      (p) => p.title == show.title,
      orElse: () => fail('not in subscriptions: ${show.title}; got ${subscribed.map((p) => p.title).toList()}'),
    );

    // The server imports the feed's episodes in the background.
    var episodes = await service.getPodcastEpisodes(userId, podcast.id!);
    for (var i = 0; episodes.length < 3 && i < 60; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      episodes = await service.getPodcastEpisodes(userId, podcast.id!);
    }
    expect(episodes, hasLength(3), reason: 'the recorded feed has three episodes');
    final episode = episodes.first;

    // Playback saves positions through the outbox.
    final settings = _Settings();
    when(() => settings.castawayServer).thenReturn(_server);
    when(() => settings.castawayApiKey).thenReturn(service.apiKey);
    final repository = newInMemoryRepository();
    final outbox = OfflineActionQueue(repository: repository, castawayService: service, settingsService: settings);
    await outbox.enqueuePosition(episode.episodeId, userId, _position, false);
    for (var i = 0; (await repository.getPendingActions()).isNotEmpty && i < 30; i++) {
      await outbox.flush();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(await repository.getPendingActions(), isEmpty, reason: 'the outbox sent the position');
    outbox.dispose();

    if (_out != null) {
      File(_out!).writeAsStringSync(jsonEncode({
        'episode_id': episode.episodeId,
        'episode_title': episode.episodeTitle,
        'position': _position.round(),
      }));
    }
  }, skip: _server == null ? 'run by tests/real-flow/run.sh against the real server' : null, timeout: const Timeout(Duration(minutes: 3)));
}
