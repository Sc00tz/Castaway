// The app used to rewrite every http:// address it read (feed, audio, artwork, chapters,
// transcripts, people, funding) to https://. A podcast served only over plain http then had
// the wrong feed address on the phone and audio that wouldn't load. Addresses are now kept
// exactly as the feed and the server give them.

import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/chapter.dart';
import 'package:castaway_mobile/entities/episode.dart';
import 'package:castaway_mobile/entities/funding.dart';
import 'package:castaway_mobile/entities/person.dart';
import 'package:castaway_mobile/entities/podcast.dart';
import 'package:castaway_mobile/entities/transcript.dart';

const _feed = 'http://podcasts.example.com/feed.xml';
const _audio = 'http://media.example.com/episode-1.mp3';
const _art = 'http://media.example.com/art.jpg';

void main() {
  test('a podcast keeps an http feed address and artwork', () {
    final podcast = Podcast(guid: _feed, url: _feed, link: 'http://example.com', title: 'Show', imageUrl: _art, thumbImageUrl: _art);
    expect(podcast.url, _feed);
    expect(podcast.imageUrl, _art);
    expect(podcast.thumbImageUrl, _art);
  });

  test('an episode keeps http audio, artwork and chapter addresses', () {
    final episode = Episode(
      guid: 'ep-1',
      podcast: 'Show',
      contentUrl: _audio,
      imageUrl: _art,
      thumbImageUrl: _art,
      chaptersUrl: 'http://media.example.com/chapters.json',
    );
    expect(episode.contentUrl, _audio);
    expect(episode.imageUrl, _art);
    expect(episode.thumbImageUrl, _art);
    expect(episode.chaptersUrl, 'http://media.example.com/chapters.json');
  });

  test('chapters, transcripts, people and funding links keep http', () {
    expect(Chapter(title: 'c', imageUrl: _art, startTime: 0, url: 'http://example.com/c').url, 'http://example.com/c');
    expect(Chapter(title: 'c', imageUrl: _art, startTime: 0).imageUrl, _art);
    expect(TranscriptUrl(url: 'http://example.com/t.srt', type: TranscriptFormat.subrip).url, 'http://example.com/t.srt');
    final person = Person(name: 'Host', image: _art, link: 'http://example.com/host');
    expect(person.image, _art);
    expect(person.link, 'http://example.com/host');
    expect(Funding(url: 'http://example.com/support', value: 'Support').url, 'http://example.com/support');
  });

  test('https addresses are untouched too', () {
    expect(Podcast(guid: 'g', url: 'https://example.com/f.xml', link: '', title: 't').url, 'https://example.com/f.xml');
  });
}
