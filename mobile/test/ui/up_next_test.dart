// Up Next leaves out the episode that's playing. When that's the only queued episode, it used to
// say "Your queue is empty" while the Queue screen listed it.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/l10n/app_localizations.dart';
import 'package:castaway_mobile/ui/podcast/castaway_up_next_view.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  test('only the playing episode is queued: nothing after it, not an empty queue', () {
    expect(upNextEmptyMessage(l, playingIsQueued: true), 'Nothing is queued after this episode.');
  });

  test('nothing queued at all: the queue is empty', () {
    expect(upNextEmptyMessage(l, playingIsQueued: false), l.up_next_empty);
  });
}
