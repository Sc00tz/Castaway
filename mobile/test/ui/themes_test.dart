import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/ui/themes.dart';

void main() {
  group('ThemeRegistry.normalizeKey', () {
    test('keeps exact keys', () {
      expect(ThemeRegistry.normalizeKey('Nordic Light'), 'Nordic Light');
    });

    test('matches server names regardless of case', () {
      expect(ThemeRegistry.normalizeKey('light'), 'Light');
      expect(ThemeRegistry.normalizeKey('NORDIC'), 'Nordic');
    });

    test('falls back to Castaway Dark for unknown names', () {
      expect(ThemeRegistry.normalizeKey('My Custom Theme'), 'Castaway Dark');
    });

    test('Castaway Dark and Castaway Light are listed first, and the web\'s names match', () {
      expect(ThemeRegistry.themeKeys.take(2), ['Castaway Dark', 'Castaway Light']);
      expect(ThemeRegistry.normalizeKey('castaway dark'), 'Castaway Dark');
    });

    test('always yields exactly one dropdown item', () {
      for (final stored in ['light', 'Dark', 'My Custom Theme']) {
        final key = ThemeRegistry.normalizeKey(stored);
        expect(ThemeRegistry.themeList.where((t) => t.key == key).length, 1);
      }
    });
  });
}
