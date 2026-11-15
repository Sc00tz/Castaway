import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/app_settings.dart';

void main() {
  group('sensibleDefaults', () {
    test('produces a usable dark-theme, iTunes-search, no-account default state', () {
      final settings = AppSettings.sensibleDefaults();

      expect(settings.theme, 'Dark');
      expect(settings.searchProvider, 'itunes');
      expect(settings.playbackSpeed, 1.0);
      expect(settings.autoUpdateEpisodePeriod, -1);
      expect(settings.showFunding, isTrue);
      expect(settings.castawayServer, isNull);
      expect(settings.castawayUserId, isNull);
      expect(settings.bottomBarOrder, isNotEmpty);
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
      expect(updated.bottomBarOrder, base.bottomBarOrder);
    });

    test('calling copyWith with no arguments returns an equivalent settings object', () {
      final base = AppSettings.sensibleDefaults();
      final copy = base.copyWith();

      expect(copy.theme, base.theme);
      expect(copy.castawayServer, base.castawayServer);
      expect(copy.bottomBarOrder, base.bottomBarOrder);
    });
  });

  group('normalizeBottomBarOrder', () {
    test('a saved order from before People keeps its order and gains People at the end', () {
      final saved = ['Search', 'Home', 'Feed', 'Saved', 'Podcasts', 'Downloads', 'History', 'Playlists'];
      expect(normalizeBottomBarOrder(saved), [...saved, 'Discover', 'People']);
    });

    test('Discover is a page, and an order saved before it gains it at the end', () {
      expect(defaultBottomBarOrder, contains('Discover'));
      final saved = ['Home', 'Feed', 'Saved', 'Podcasts', 'People', 'Downloads', 'History', 'Playlists', 'Search'];
      expect(normalizeBottomBarOrder(saved), [...saved, 'Discover']);
    });

    test('unknown and duplicate entries are dropped', () {
      final order = normalizeBottomBarOrder(['Home', 'Bogus', 'Home', ...defaultBottomBarOrder]);
      expect(order, defaultBottomBarOrder);
    });
  });
}
