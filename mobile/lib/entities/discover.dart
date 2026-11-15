// lib/entities/discover.dart
//
// What the Discover screen shows: trending shows and categories (Podcast Index's when the server
// has a key, otherwise Apple's charts, in the same shape) and "For You" suggestions.

import 'package:castaway_mobile/entities/castaway_search.dart';

/// A category for "Browse by category". Only the name is sent back to the server.
class DiscoverCategory {
  final int id;
  final String name;

  const DiscoverCategory({required this.id, required this.name});

  factory DiscoverCategory.fromJson(Map<String, dynamic> json) => DiscoverCategory(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
      );
}

/// The server's trending answer: `{"feeds": [...]}`. Apple shows have no Podcast Index id, so
/// they're added by feed address (indexId 0), like Apple search results.
List<UnifiedCastawayPodcast> trendingFromJson(Map<String, dynamic> json) {
  final feeds = json['feeds'] as List<dynamic>? ?? const [];
  return feeds
      .whereType<Map<String, dynamic>>()
      .map(_trendingFeed)
      .where((p) => p.title.isNotEmpty && p.url.isNotEmpty)
      .toList();
}

UnifiedCastawayPodcast _trendingFeed(Map<String, dynamic> f) {
  final id = (f['id'] as num?)?.toInt() ?? 0;
  final image = (f['image'] as String?)?.isNotEmpty == true ? f['image'] as String : (f['artwork'] as String? ?? '');
  final artwork = (f['artwork'] as String?)?.isNotEmpty == true ? f['artwork'] as String : image;
  final url = f['url'] as String? ?? '';
  final author = f['author'] as String? ?? '';
  return UnifiedCastawayPodcast(
    id: id,
    indexId: id,
    title: f['title'] as String? ?? '',
    url: url,
    originalUrl: url,
    link: '',
    description: f['description'] as String? ?? '',
    author: author,
    ownerName: author,
    image: image,
    artwork: artwork,
    lastUpdateTime: (f['newestItemPublishTime'] as num?)?.toInt() ?? 0,
    categories: _categories(f['categories']),
    explicit: false,
    episodeCount: (f['episodeCount'] as num?)?.toInt() ?? 0,
  );
}

Map<String, String>? _categories(Object? raw) {
  if (raw is! Map) return null;
  return {for (final e in raw.entries) e.key.toString(): e.value.toString()};
}

/// One "For You" suggestion, with why it was suggested ("Because you listen to …").
class Recommendation {
  final UnifiedCastawayPodcast podcast;
  final String reason;

  const Recommendation({required this.podcast, required this.reason});

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    final id = (json['podcastindexid'] as num?)?.toInt() ?? 0;
    final url = json['feedurl'] as String? ?? '';
    final image = json['image'] as String? ?? '';
    final author = json['author'] as String? ?? '';
    return Recommendation(
      reason: json['reason'] as String? ?? '',
      podcast: UnifiedCastawayPodcast(
        id: id,
        indexId: id,
        title: json['title'] as String? ?? '',
        url: url,
        originalUrl: url,
        link: '',
        description: json['description'] as String? ?? '',
        author: author,
        ownerName: author,
        image: image,
        artwork: image,
        lastUpdateTime: 0,
        categories: _categories(json['categories']),
        explicit: false,
        episodeCount: 0,
      ),
    );
  }
}

/// Suggestions grouped by reason, strongest reason first (the server sends them best first).
List<(String reason, List<UnifiedCastawayPodcast> podcasts)> groupByReason(List<Recommendation> recs) {
  final groups = <String, List<UnifiedCastawayPodcast>>{};
  for (final r in recs) {
    if (r.podcast.title.isEmpty || r.podcast.url.isEmpty) continue;
    groups.putIfAbsent(r.reason, () => []).add(r.podcast);
  }
  return [for (final e in groups.entries) (e.key, e.value)];
}
