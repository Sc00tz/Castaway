// lib/entities/youtube_channel.dart

/// Feed URL the server stores for a subscribed YouTube channel.
String youtubeChannelUrl(String channelId) => 'https://www.youtube.com/channel/$channelId';

bool isYoutubeChannelUrl(String url) => url.startsWith('https://www.youtube.com/channel/');

/// Which new videos a channel subscription adds. Null means no limit.
class YouTubeVideoFilter {
  final int? minMinutes;
  final int? maxMinutes;
  final String? titleContains;

  const YouTubeVideoFilter({this.minMinutes, this.maxMinutes, this.titleContains});

  factory YouTubeVideoFilter.fromJson(Map<String, dynamic> json) {
    return YouTubeVideoFilter(
      minMinutes: _asInt(json['min_minutes']),
      maxMinutes: _asInt(json['max_minutes']),
      titleContains: json['title_contains'] as String?,
    );
  }
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}
