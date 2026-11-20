import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/app_settings.dart';

void main() {
  group('sensibleDefaults', () {
    test('produces a usable dark-theme, iTunes-search, no-account default state', () {
      final settings = AppSettings.sensibleDefaults();

      expect(settings.theme, 'Castaway Dark');
      expect(settings.searchProvider, 'itunes');
      expect(settings.playbackSpeed, 1.0);
      expect(settings.autoUpdateEpisodePeriod, -1);
      expect(settings.showFunding, isTrue);
      expect(settings.castawayServer, isNull);
      expect(settings.castawayUserId, isNull);
    });
  });

  group('copyWith', () {
    test('overrides only the specified fields, keeping the rest', () {
      final base = AppSettings.sensibleDefaults();

      final updated = base.copyWith(theme: 'Light', castawayUserId: 42);

      expect(updated.theme, 'Light');
      expect(updated.castawayUserId, 42);
      // Untouched fields carry over from the original.
      expect(updated.searchProvider, base.searchProvider);
      expect(updated.playbackSpeed, base.playbackSpeed);
    });

    test('calling copyWith with no arguments returns an equivalent settings object', () {
      final base = AppSettings.sensibleDefaults();
      final copy = base.copyWith();

      expect(copy.theme, base.theme);
      expect(copy.castawayServer, base.castawayServer);
    });
  });
}
