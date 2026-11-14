// History, Queue, Saved, Downloads, playlists, the podcast page and the people
// pages showed the position from when they were opened and didn't move while
// an episode played. They now take every position this phone records.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';
import 'package:castaway_mobile/ui/utils/position_utils.dart';
import 'package:castaway_mobile/ui/widgets/live_positions.dart';

import '../support/factories.dart';

final _positions = StreamController<PositionUpdate>.broadcast();

/// A minimal episode list built the way the real screens are.
class _List extends StatefulWidget {
  final List<CastawayEpisode> initial;
  const _List(this.initial);

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> with LivePositions<_List> {
  late List<CastawayEpisode> episodes = widget.initial;
  int builds = 0;

  @override
  Stream<PositionUpdate>? get livePositionStream => _positions.stream;

  @override
  bool applyLivePosition(PositionUpdate update) {
    final updated = PositionUtils.applyUpdate(episodes, update);
    if (identical(updated, episodes)) return false;
    episodes = updated;
    return true;
  }

  /// What a screen does with a page it loads after positions were recorded.
  void load(List<CastawayEpisode> page) => setState(() => episodes = withLivePositions(page));

  @override
  Widget build(BuildContext context) {
    builds++;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [for (final e in episodes) Text('${e.episodeId}: ${e.listenDuration}')]),
    );
  }
}

/// Record a position the way the outbox does, then let the screen redraw.
Future<void> record(WidgetTester tester, PositionUpdate update) async {
  _positions.add(update);
  await tester.pump(); // the stream delivers on the next tick
  await tester.pump(); // the rebuild it asked for
}

void main() {
  testWidgets('a list moves with the position the phone records while playing', (tester) async {
    await tester.pumpWidget(_List([
      buildCastawayEpisode(episodeId: 1, listenDuration: 100),
      buildCastawayEpisode(episodeId: 2, listenDuration: 50),
    ]));
    expect(find.text('1: 100'), findsOneWidget);

    await record(tester, const PositionUpdate(1, false, 115)); // the 15-second save
    expect(find.text('1: 115'), findsOneWidget);

    await record(tester, const PositionUpdate(1, false, 1800)); // skipped ahead
    expect(find.text('1: 1800'), findsOneWidget);
    expect(find.text('2: 50'), findsOneWidget);
  });

  testWidgets('positions for episodes not on the list don\'t rebuild it', (tester) async {
    await tester.pumpWidget(_List([buildCastawayEpisode(episodeId: 1, listenDuration: 100)]));
    final state = tester.state<_ListState>(find.byType(_List));
    final before = state.builds;

    _positions.add(const PositionUpdate(9, false, 30));
    await record(tester, const PositionUpdate(1, true, 30)); // a YouTube video with the same id
    expect(state.builds, before);
    expect(find.text('1: 100'), findsOneWidget);
  });

  testWidgets('a page loaded after a save keeps the newer position', (tester) async {
    await tester.pumpWidget(_List(const []));
    await record(tester, const PositionUpdate(1, false, 900));

    // The server answered with the position from before that save.
    tester.state<_ListState>(find.byType(_List)).load([buildCastawayEpisode(episodeId: 1, listenDuration: 600)]);
    await tester.pump();
    expect(find.text('1: 900'), findsOneWidget);
  });

  testWidgets('a closed screen stops listening', (tester) async {
    await tester.pumpWidget(_List([buildCastawayEpisode(episodeId: 1, listenDuration: 100)]));
    expect(_positions.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(_positions.hasListener, isFalse);
  });

  test('every episode list takes live positions', () {
    // Home and the Feed have their own handling; these are the rest.
    const screens = [
      'lib/ui/castaway/history.dart',
      'lib/ui/castaway/queue.dart',
      'lib/ui/castaway/saved.dart',
      'lib/ui/castaway/downloads.dart',
      'lib/ui/castaway/playlist_episodes.dart',
      'lib/ui/castaway/podcast_details.dart',
      'lib/ui/castaway/people/person_page.dart',
      'lib/ui/castaway/people/followed_people.dart',
    ];
    for (final path in screens) {
      final source = File(path).readAsStringSync();
      expect(source, contains('LivePositions<'), reason: '$path should mix in LivePositions');
      expect(source, contains('bool applyLivePosition('), reason: path);
    }
  });
}
