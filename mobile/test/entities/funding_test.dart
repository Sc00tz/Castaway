import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/funding.dart';

void main() {
  group('toMap/fromMap', () {
    test('round-trips url and value', () {
      final original = Funding(url: 'https://example.com/donate', value: 'Support the show');
      final restored = Funding.fromMap(original.toMap());

      expect(restored.url, original.url);
      expect(restored.value, original.value);
    });
  });
}
