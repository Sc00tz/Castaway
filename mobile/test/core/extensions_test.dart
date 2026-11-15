import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/core/extensions.dart';

void main() {
  group('IterableExtensions.chunk', () {
    test('splits a list into equal-sized chunks', () {
      final result = [1, 2, 3, 4, 5, 6].chunk(2).toList();

      expect(result, [
        [1, 2],
        [3, 4],
        [5, 6],
      ]);
    });

    test('the last chunk can be smaller than the requested size', () {
      final result = [1, 2, 3, 4, 5].chunk(2).toList();

      expect(result, [
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('yields a single empty chunk for an empty iterable', () {
      final result = <int>[].chunk(3).toList();

      expect(result, [[]]);
    });

    test('a chunk size larger than the list returns everything as one chunk', () {
      final result = [1, 2, 3].chunk(10).toList();

      expect(result, [
        [1, 2, 3],
      ]);
    });
  });

  group('ExtDouble.toTenth', () {
    test('rounds to one decimal place', () {
      expect(1.23.toTenth, 1.2);
      expect(1.26.toTenth, 1.3);
    });

    test('leaves a value already at one decimal place unchanged', () {
      expect(1.5.toTenth, 1.5);
    });

    test('rounds a whole number to itself', () {
      expect(2.0.toTenth, 2.0);
    });
  });
}
