import 'package:flutter_test/flutter_test.dart';
import 'package:pinepods_mobile/ui/widgets/hide_played.dart';

/// Applies a move the way the queue does (ReorderableList's convention), to check where things
/// end up in the full list.
List<String> applyMove(List<String> full, int from, int to) {
  final list = [...full];
  if (to > from) to -= 1;
  list.insert(to, list.removeAt(from));
  return list;
}

void main() {
  group('visibleMoveToFull', () {
    // Full queue: a b* c d* e, where * are played and hidden. Shown: a c e (indices 0 2 4).
    const full = ['a', 'b*', 'c', 'd*', 'e'];
    const visible = [0, 2, 4];

    test('dragging the last shown item to the top lands before the first shown one', () {
      final (from, to) = visibleMoveToFull(visible, 2, 0);
      expect(applyMove(full, from, to), ['e', 'a', 'b*', 'c', 'd*']);
    });

    test('dragging the first shown item to the end lands after the last shown one', () {
      final (from, to) = visibleMoveToFull(visible, 0, 3);
      expect(applyMove(full, from, to), ['b*', 'c', 'd*', 'e', 'a']);
    });

    test('dragging down one place keeps hidden items where they were relative to others', () {
      final (from, to) = visibleMoveToFull(visible, 0, 2);
      expect(applyMove(full, from, to), ['b*', 'c', 'd*', 'a', 'e']);
    });

    test('with nothing hidden it is the plain move', () {
      final (from, to) = visibleMoveToFull([0, 1, 2], 2, 0);
      expect((from, to), (2, 0));
    });
  });
}
