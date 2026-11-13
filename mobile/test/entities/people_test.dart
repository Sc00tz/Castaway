import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pinepods_mobile/entities/people.dart';
import 'package:pinepods_mobile/services/pinepods/pinepods_service.dart';

Map<String, dynamic> _credited(String name, {int id = 1}) => {
      'id': id,
      'name': name,
      'img': '',
      'href': null,
      'role': 'host',
      'roles': ['host'],
      'group': null,
      'scope': 'podcast',
      'episode_count': 0,
      'sources': ['feed'],
      'followed': false,
    };

void main() {
  group('parsing', () {
    test('CreditedPerson treats empty image as none', () {
      final p = CreditedPerson.fromJson(_credited('Jane'));
      expect(p.img, isNull);
      expect(p.canOpen, isTrue);
    });

    test('legacy 2.0 people without ids parse but cannot be opened', () {
      final p = CreditedPerson.fromJson({'name': 'Old Host', 'role': 'host', 'img': 'https://x/y.png'});
      expect(p.id, 0);
      expect(p.canOpen, isFalse);
      expect(p.img, 'https://x/y.png');
    });

    test('PersonProfile parses library and outside-library episodes', () {
      final profile = PersonProfile.fromJson({
        'person': {'id': 7, 'name': 'Jane', 'followed': true},
        'podcasts': [
          {'podcastid': null, 'podcastname': 'Elsewhere Show', 'feedurl': 'https://f', 'roles': ['guest'], 'podcast_level': false, 'episode_count': 2},
        ],
        'episodes': [
          {'podcastid': 3, 'podcastname': 'Mine', 'episodetitle': 'Ep', 'episodepubdate': '2026-10-01', 'episodedescription': '', 'episodeartwork': '', 'episodeurl': 'u1', 'episodeduration': 60, 'episodeid': 11, 'completed': false, 'saved': false, 'queued': false, 'downloaded': false, 'is_youtube': false, 'is_video': false},
        ],
        'external_episodes': [
          {'episodeid': 0, 'podcastid': 0, 'podcastname': 'Elsewhere Show', 'feedurl': 'https://f', 'episodetitle': 'Guest spot', 'episodepubdate': '2026-09-01', 'episodedescription': '', 'episodeartwork': '', 'episodeurl': 'u2', 'episodeduration': 0, 'completed': false, 'saved': false, 'queued': false, 'downloaded': false, 'is_youtube': false, 'is_video': false, 'role': 'guest'},
        ],
        'refreshing': true,
      });
      expect(profile.person.followed, isTrue);
      expect(profile.podcasts.single.inLibrary, isFalse);
      expect(profile.episodes.single.episodeId, 11);
      expect(profile.externalEpisodes.single.episodeId, 0);
      expect(profile.refreshing, isTrue);
    });
  });

  group('PinepodsService people', () {
    PinepodsService service(MockClientHandler handler) =>
        PinepodsService(client: MockClient(handler))..setCredentials('https://pods.example.com', 'key');

    test('podcast people come from the people endpoint', () async {
      Uri? url;
      final s = service((request) async {
        url = request.url;
        return http.Response(jsonEncode({'people': [_credited('Host')], 'guests': [_credited('Guest', id: 2)]}), 200);
      });
      final credits = await s.getPodcastPeople(5);
      expect(url.toString(), 'https://pods.example.com/api/data/people/podcast/5');
      expect(credits!.people.single.name, 'Host');
      expect(credits.guests.single.id, 2);
    });

    test('an older server without the endpoint gives null, for the fallback', () async {
      final s = service((request) async => http.Response('not found', 404));
      expect(await s.getPodcastPeople(5), isNull);
      expect(await s.getEpisodePeople(5), isNull);
    });

    test('unfollow uses DELETE', () async {
      String? method;
      final s = service((request) async {
        method = request.method;
        return http.Response('{"following": false}', 200);
      });
      expect(await s.setPersonFollowed(9, false), isTrue);
      expect(method, 'DELETE');
    });
  });
}
