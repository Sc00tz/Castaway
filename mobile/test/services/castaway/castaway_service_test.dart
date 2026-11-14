// Regression tests for CastawayService's HTTP handling: before this fix every
// request used the top-level http.get/post/put functions (a fresh
// http.Client per call, no timeout), so a stalled request hung forever with
// no feedback. These tests inject a fake http.Client (package:http/testing.dart)
// to verify the shared client + timeout wrapper actually behaves as intended.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:castaway_mobile/services/castaway/login_service.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';

void main() {
  group('CastawayService HTTP client', () {
    test('a normal response still resolves correctly through the wrapper', () async {
      Uri? capturedUrl;
      final client = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response('{"castaway_instance": true}', 200);
      });
      final service = CastawayService(client: client);

      final result = await service.verifyCastawayInstance('https://pods.example.com');

      expect(result, isTrue);
      expect(capturedUrl.toString(), 'https://pods.example.com/api/castaway_check');
    });

    test('a server from before 0.10.2 is found at the old check address', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return request.url.path == '/api/castaway_check'
            ? http.Response('Not Found', 404)
            : http.Response('{"status_code": 200, "pinepods_instance": true}', 200);
      });
      final service = CastawayService(client: client);

      expect(await service.verifyCastawayInstance('https://pods.example.com'), isTrue);
      expect(paths, ['/api/castaway_check', CastawayLoginService.legacyCheckPath]);
    });

    test('Podcast Index search without a key on the server searches Apple instead', () async {
      final indexes = <String?>[];
      final client = MockClient((request) async {
        final index = request.url.queryParameters['index'];
        indexes.add(index);
        if (index == 'podcast_index') {
          return http.Response('{"message": "Podcast Index needs an API key"}', 503);
        }
        return http.Response(
            '{"resultCount": 1, "results": [{"trackId": 6785225885, "collectionId": 6785225885, '
            '"trackName": "Big Id Show", "artistName": "Host", "feedUrl": "https://feeds.example.invalid/x.xml"}]}',
            200);
      });
      final service = CastawayService(client: client)..setCredentials('https://pods.example.com', 'key');

      final result = await service.searchPodcasts('show', SearchProvider.podcastIndex);

      expect(indexes, ['podcast_index', 'itunes']);
      expect(result.getUnifiedPodcasts().single.title, 'Big Id Show');
    });

    test('adding a podcast tells the screens, and again once its episodes are in', () async {
      var importChecks = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/data/add_podcast') {
          return http.Response('{"success": true, "podcast_id": 7, "first_episode_id": 0}', 200);
        }
        if (request.url.path == '/api/tasks/user/2') {
          importChecks++;
          final status = importChecks < 2 ? 'PROGRESS' : 'SUCCESS';
          return http.Response('[{"id": "t", "task_type": "add_podcast_episodes", "status": "$status", "progress": 50}]', 200);
        }
        return http.Response('', 404);
      });
      final service = CastawayService(client: client)..setCredentials('https://pods.example.com', 'key');
      final changes = <int>[];
      void listener() => changes.add(CastawayService.libraryChanged.value);
      CastawayService.libraryChanged.addListener(listener);
      addTearDown(() => CastawayService.libraryChanged.removeListener(listener));

      final podcast = UnifiedCastawayPodcast.fromITunesPodcast(CastawayITunesPodcast.fromJson(
          {'trackId': 1, 'trackName': 'New Show', 'feedUrl': 'https://feeds.example.invalid/n.xml'}));
      expect(await service.addPodcast(podcast, 2), isTrue);
      expect(changes, hasLength(1), reason: 'the new podcast shows right away');

      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(importChecks, 2);
      expect(changes, hasLength(2), reason: 'and its episodes once the import is done');
    });

    test('a request that never responds times out instead of hanging forever', () async {
      // Simulates a stalled connection: the handler's future never completes.
      final client = MockClient((request) => Completer<http.Response>().future);
      final service = CastawayService(client: client, timeout: const Duration(milliseconds: 50));

      final stopwatch = Stopwatch()..start();
      final result = await service.verifyCastawayInstance('https://pods.example.com');
      stopwatch.stop();

      // Before this fix there was no timeout at all, so this call would have
      // hung indefinitely rather than failing fast.
      expect(result, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('the client is reused across requests rather than recreated each call', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('{"castaway_instance": true}', 200);
      });
      final service = CastawayService(client: client);

      final first = await service.verifyCastawayInstance('https://pods.example.com');
      final second = await service.verifyCastawayInstance('https://pods.example.com');

      expect(first, isTrue);
      expect(second, isTrue);
      expect(callCount, 2);
    });
  });
}
