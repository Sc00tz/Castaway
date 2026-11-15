// The phone reads Discover from the server's real answers (Apple's charts without a Podcast
// Index key): trending, categories and "For You".

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/discover.dart';

import '../fixtures/discover_answers.dart';

void main() {
  test('trending shows from Apple become podcasts added by feed address', () {
    final shows = trendingFromJson(jsonDecode(trendingAnswer) as Map<String, dynamic>);
    expect(shows.map((s) => s.title), ['The Ezra Klein Show', 'Stuff You Should Know']);
    final first = shows.first;
    expect(first.indexId, 0, reason: 'Apple shows have no Podcast Index id');
    expect(first.url, startsWith('http'));
    expect(first.artwork, contains('600x600'));
    expect(first.author, isNotEmpty);
    expect(first.description, isNotEmpty);
    expect(first.episodeCount, greaterThan(0));
    expect(first.categories, isNotEmpty);
  });

  test('a Podcast Index trending feed keeps its id', () {
    final shows = trendingFromJson({
      'feeds': [
        {'id': 920666, 'title': 'Indexed Show', 'url': 'https://feeds.example.com/i.xml', 'image': 'https://img.example.com/i.jpg'},
      ],
    });
    expect(shows.single.indexId, 920666);
    expect(shows.single.artwork, 'https://img.example.com/i.jpg', reason: 'artwork falls back to image');
  });

  test('shows without a title or feed address are left out', () {
    final shows = trendingFromJson({
      'feeds': [
        {'title': '', 'url': 'https://x/f.xml'},
        {'title': 'No Feed', 'url': ''},
      ],
    });
    expect(shows, isEmpty);
  });

  test('categories', () {
    final feeds = (jsonDecode(categoriesAnswer) as Map<String, dynamic>)['feeds'] as List<dynamic>;
    final categories = feeds.cast<Map<String, dynamic>>().map(DiscoverCategory.fromJson).toList();
    expect(categories.first.name, 'Arts');
    expect(categories.first.id, 1301);
  });

  test('For You suggestions are grouped by reason, in the server\'s order', () {
    final recs = (jsonDecode(recommendationsAnswer) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(Recommendation.fromJson)
        .toList();
    expect(recs.first.podcast.indexId, 0);
    expect(recs.first.podcast.url, startsWith('http'));
    final groups = groupByReason(recs);
    expect(groups.single.$1, 'Because you listen to Arts');
    expect(groups.single.$2.map((p) => p.title), ['The iDesign Lab Podcast', 'Fresh Air', 'The Magnus Archives']);
  });
}
