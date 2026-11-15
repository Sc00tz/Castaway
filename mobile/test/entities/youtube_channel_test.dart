import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/youtube_channel.dart';

void main() {
  test('channel feed URLs', () {
    expect(isYoutubeChannelUrl(youtubeChannelUrl('UCabc')), isTrue);
    expect(isYoutubeChannelUrl('https://feeds.example.com/pod.xml'), isFalse);
  });

  test('YouTubeVideoFilter.fromJson leaves unset limits null', () {
    final filter = YouTubeVideoFilter.fromJson({'min_minutes': 5, 'max_minutes': null});
    expect(filter.minMinutes, 5);
    expect(filter.maxMinutes, isNull);
    expect(filter.titleContains, isNull);
  });
}
