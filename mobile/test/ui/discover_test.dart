// The phone's Discover screen: For You grouped by reason, Trending by category, and following a
// show from it. The server client is faked; its answers are real recorded ones.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/entities/discover.dart';
import 'package:castaway_mobile/l10n/app_localizations.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/castaway/discover.dart';

import '../fixtures/discover_answers.dart';

class _Service extends Mock implements CastawayService {}

List<UnifiedCastawayPodcast> _trending() => trendingFromJson(jsonDecode(trendingAnswer) as Map<String, dynamic>);

UnifiedCastawayPodcast _show(String title) => trendingFromJson({
      'feeds': [
        {'title': title, 'url': 'https://feeds.example.com/${title.length}.xml'},
      ],
    }).single;

void main() {
  late _Service service;

  setUpAll(() => registerFallbackValue(_show('fallback')));

  setUp(() {
    service = _Service();
    when(() => service.getUserIdFromApiKey()).thenAnswer((_) async => 2);
    when(() => service.getUserPodcasts(any())).thenAnswer((_) async => []);
    when(() => service.getRecommendations(refresh: any(named: 'refresh'))).thenAnswer((_) async =>
        (jsonDecode(recommendationsAnswer) as List<dynamic>).cast<Map<String, dynamic>>().map(Recommendation.fromJson).toList());
    when(() => service.getDiscoverCategories()).thenAnswer((_) async => const [
          DiscoverCategory(id: 1301, name: 'Arts'),
          DiscoverCategory(id: 1324, name: 'Society & Culture'),
        ]);
    when(() => service.getTrending(category: any(named: 'category'))).thenAnswer((_) async => _trending());
    when(() => service.getTrending(category: 'Arts')).thenAnswer((_) async => [_show('Arts Chart Topper')]);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CustomScrollView(slivers: [CastawayDiscover(service: service)])),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows For You grouped by reason, and Trending', (tester) async {
    await open(tester);
    expect(find.text('For You'), findsOneWidget);
    expect(find.text('Because you listen to Arts'), findsOneWidget);
    expect(find.text('Fresh Air'), findsOneWidget);
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('The Ezra Klein Show'), findsOneWidget);
    expect(find.text('Society & Culture'), findsOneWidget, reason: 'category chips');
  });

  testWidgets('a category chip shows that category\'s trending shows', (tester) async {
    await open(tester);
    await tester.tap(find.text('Arts'));
    await tester.pumpAndSettle();
    verify(() => service.getTrending(category: 'Arts')).called(1);
    expect(find.text('Arts Chart Topper'), findsOneWidget);
    expect(find.text('The Ezra Klein Show'), findsNothing);
  });

  testWidgets('the follow button subscribes to the show', (tester) async {
    when(() => service.addPodcast(any(), any())).thenAnswer((_) async => true);
    await open(tester);
    final card = find.ancestor(of: find.text('The Ezra Klein Show'), matching: find.byType(Card));
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('Follow')));
    await tester.pumpAndSettle();
    final added = verify(() => service.addPodcast(captureAny(), 2)).captured.single as UnifiedCastawayPodcast;
    expect(added.title, 'The Ezra Klein Show');
    expect(find.descendant(of: card, matching: find.byTooltip('Unfollow')), findsOneWidget);
  });

  testWidgets('without suggestions it says how to get them, and still shows Trending', (tester) async {
    when(() => service.getRecommendations(refresh: any(named: 'refresh'))).thenThrow(Exception('offline'));
    await open(tester);
    expect(find.text('Follow a few podcasts and shows you might like will appear here.'), findsOneWidget);
    expect(find.text('The Ezra Klein Show'), findsOneWidget);
  });

  testWidgets('refresh asks the server to work suggestions out again', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    verify(() => service.getRecommendations(refresh: true)).called(1);
  });
}
