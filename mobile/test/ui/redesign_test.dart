// The Pocket Casts-style redesign (2026-11-19): four tabs, the Lists tab and
// its counts, the Podcasts grid's new-episode badge, and readable colours in
// every theme.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:castaway_mobile/entities/home_data.dart';
import 'package:castaway_mobile/entities/podcast.dart';
import 'package:castaway_mobile/l10n/app_localizations.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/castaway/lists.dart';
import 'package:castaway_mobile/ui/themes.dart';
import 'package:castaway_mobile/ui/widgets/castaway_bottom_nav.dart';
import 'package:castaway_mobile/ui/widgets/castaway_podcast_grid_tile.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';

class _Service extends Mock implements CastawayService {}

Widget _app(Widget child, {String theme = 'Castaway Dark'}) => MaterialApp(
      theme: ThemeRegistry.getThemeData(theme),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('bottom bar', () {
    testWidgets('has Podcasts, Lists, Discover and Profile, in that order', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(_app(CastawayBottomNav(selectedIndex: 0, onSelect: picked.add)));

      final labels = ['Podcasts', 'Lists', 'Discover', 'Profile'];
      final xs = [for (final l in labels) tester.getCenter(find.text(l)).dx];
      expect(xs, [...xs]..sort(), reason: 'left to right in this order');
      expect(find.text('Home'), findsNothing);
      expect(find.text('More'), findsNothing);

      await tester.tap(find.text('Lists'));
      await tester.tap(find.text('Profile'));
      expect(picked, [CastawayTab.lists.index, CastawayTab.profile.index]);
    });
  });

  group('Lists tab', () {
    testWidgets('shows every list, the counts the server reports, and the user\'s playlists', (tester) async {
      final service = _Service();
      when(() => service.getUserPlaylists(7)).thenAnswer((_) async => [
            // What the server really sends: the account's copy isn't flagged as built-in.
            PlaylistData.fromJson({'playlist_id': 1, 'name': 'Currently Listening', 'is_system_playlist': false, 'episode_count': 6}),
            PlaylistData.fromJson({'playlist_id': 2, 'name': 'Commute', 'episode_count': 11}),
          ]);
      when(() => service.getHomeOverview(7)).thenAnswer(
          (_) async => HomeOverview.fromJson({'saved_count': 18, 'queue_count': 3, 'downloaded_count': 9}));

      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(CustomScrollView(slivers: [CastawayLists(service: service, userId: 7)])));
      await tester.pumpAndSettle();

      for (final name in ['Lists', 'Home', 'New Releases', 'In Progress', 'Up Next', 'Saved', 'Downloads', 'History']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      String countOf(String key) => tester
          .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
          .map((t) => t.data)
          .join('|');
      expect(countOf('list-inProgress'), contains('6'), reason: 'In Progress is the Currently Listening playlist');
      expect(countOf('list-upNext'), contains('3'));
      expect(countOf('list-saved'), contains('18'));
      expect(find.text('Currently Listening'), findsNothing, reason: 'shown as In Progress, not twice');
      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('New playlist'), findsOneWidget);
    });
  });

  group('Podcasts grid badge', () {
    Podcast pod(int count) => Podcast(
          id: 5,
          guid: 'g',
          url: 'https://example.com/feed.xml',
          link: '',
          title: 'Weekly',
          imageUrl: '',
          newEpisodeCount: count,
        );

    Future<void> show(WidgetTester tester, int count) => tester.pumpWidget(
          _app(Center(child: SizedBox(width: 120, height: 120, child: CastawayPodcastGridTile(podcast: pod(count))))),
        );

    testWidgets('shows the number of new episodes', (tester) async {
      await show(tester, 3);
      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('Weekly, 3 new'), findsOneWidget);
    });

    testWidgets('caps at 99+', (tester) async {
      await show(tester, 150);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('has no badge without new episodes', (tester) async {
      await show(tester, 0);
      expect(find.byKey(const ValueKey('new-badge-5')), findsNothing);
    });
  });

  group('colours', () {
    test('Castaway Dark and Light use the brand palette', () {
      expect(ThemeRegistry.getThemeData('Castaway Dark').scaffoldBackgroundColor, const Color(0xff18273a));
      expect(ThemeRegistry.getThemeData('Castaway Dark').colorScheme.secondary, const Color(0xffee6747));
      expect(ThemeRegistry.getThemeData('Castaway Light').colorScheme.secondary, const Color(0xffee6747));
    });

    for (final key in ['Castaway Light', 'Castaway Dark']) {
      test('$key: text, links and the play button meet WCAG AA', () {
        final s = CastawayStyle.fromTheme(ThemeRegistry.getThemeData(key));
        expect(contrastRatio(s.text, s.background), greaterThanOrEqualTo(7));
        expect(contrastRatio(s.muted, s.background), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(s.link, s.background), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(s.accentText, s.background), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(s.onAccent, s.accent), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(s.text, s.surface), greaterThanOrEqualTo(4.5));
      });
    }

    test('every theme gets readable secondary text and links', () {
      for (final t in ThemeRegistry.themeList) {
        final s = CastawayStyle.fromTheme(ThemeRegistry.getThemeData(t.key));
        expect(contrastRatio(s.muted, s.background), greaterThanOrEqualTo(4.5), reason: t.key);
        expect(contrastRatio(s.link, s.background), greaterThanOrEqualTo(4.5), reason: t.key);
      }
    });
  });
}
