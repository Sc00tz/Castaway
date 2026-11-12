// The offline outbox must never lose listening progress. Failed uploads used to
// be treated as sent (the service reports failure by returning false), so
// positions silently vanished and the server, and Home, fell behind.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pinepods_mobile/repository/sembast/sembast_repository.dart';
import 'package:pinepods_mobile/services/offline/offline_action_queue.dart';
import 'package:pinepods_mobile/services/pinepods/pinepods_service.dart';
import 'package:pinepods_mobile/services/settings/settings_service.dart';

import '../../support/in_memory_repository.dart';

class MockPinepodsService extends Mock implements PinepodsService {}

class MockSettingsService extends Mock implements SettingsService {}

void main() {
  late MockPinepodsService api;
  late SembastRepository repository;
  late OfflineActionQueue queue;

  setUpAll(() => registerFallbackValue(DateTime(2000)));

  setUp(() {
    api = MockPinepodsService();
    final settings = MockSettingsService();
    when(() => settings.pinepodsServer).thenReturn('https://pods.test');
    when(() => settings.pinepodsApiKey).thenReturn('key');
    repository = newInMemoryRepository();
    queue = OfflineActionQueue(repository: repository, pinepodsService: api, settingsService: settings);
    addTearDown(queue.dispose);
  });

  void uploads(Future<bool> Function() result) {
    when(() => api.recordListenDuration(any(), any(), any(), any(), recordedAt: any(named: 'recordedAt')))
        .thenAnswer((_) => result());
  }

  void serverReachable(bool reachable) {
    when(() => api.verifyPinepodsInstance(any())).thenAnswer((_) async => reachable);
  }

  Future<int?> retries() async {
    final pending = await repository.getPendingActions();
    return pending.isEmpty ? null : pending.single.retryCount;
  }

  test('a failed upload stays queued, without using up retries, while the server is unreachable', () async {
    uploads(() async => false);
    serverReachable(false);

    await queue.enqueuePosition(101, 42, 1200, false);
    for (var i = 0; i < 20; i++) {
      await queue.flush();
    }
    await pumpEventQueue();

    expect(await queue.pendingPosition(101, false), 1200);
    expect(await retries(), 0);
  });

  test('a position the server refuses is retried, then dropped after 8 refusals', () async {
    uploads(() async => false);
    serverReachable(true);

    await queue.enqueuePosition(101, 42, 1200, false);
    await pumpEventQueue();
    for (var i = 0; i < 8; i++) {
      await queue.flush();
    }

    expect(await queue.pendingPosition(101, false), isNull);
  });

  test('a sent position leaves the outbox, carrying the time it was taken', () async {
    uploads(() async => true);
    final before = DateTime.now();

    await queue.enqueuePosition(101, 42, 1200, false);
    await pumpEventQueue();

    expect(await queue.pendingPosition(101, false), isNull);
    final recordedAt = verify(
      () => api.recordListenDuration(101, 42, 1200, false, recordedAt: captureAny(named: 'recordedAt')),
    ).captured.single as DateTime;
    expect(recordedAt.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    expect(recordedAt.isAfter(DateTime.now()), isFalse);
  });

  test('a position saved while a flush is running is sent by that flush', () async {
    final firstUpload = Completer<bool>();
    var calls = 0;
    uploads(() {
      calls++;
      return calls == 1 ? firstUpload.future : Future.value(true);
    });

    await queue.enqueuePosition(101, 42, 100, false); // starts a flush that blocks
    await pumpEventQueue();
    await queue.enqueuePosition(101, 42, 115, false); // saved mid-flush (on pause, say)
    firstUpload.complete(true);
    await pumpEventQueue();

    verify(() => api.recordListenDuration(101, 42, 115, false, recordedAt: any(named: 'recordedAt'))).called(1);
    expect(await queue.pendingPosition(101, false), isNull, reason: 'the newest position was not left behind');
  });

  test('every recorded position is announced, and the newest unsent ones are listed', () async {
    serverReachable(false);
    uploads(() async => false);
    final announced = <String>[];
    final sub = queue.positionUpdates.listen((u) => announced.add('${u.key}=${u.seconds}'));
    addTearDown(sub.cancel);

    await queue.enqueuePosition(101, 42, 60, false);
    await queue.enqueuePosition(101, 42, 75, false);
    await queue.enqueuePosition(101, 42, 30, true);
    await pumpEventQueue();

    expect(announced, ['ep:101=60.0', 'ep:101=75.0', 'yt:101=30.0']);
    expect(await queue.pendingPositions(), {'ep:101': 75.0, 'yt:101': 30.0},
        reason: 'one position per episode, and YouTube ids are kept apart');
  });
}
