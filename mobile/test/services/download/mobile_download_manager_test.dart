// The phone's downloads moved from flutter_downloader to background_downloader (which
// supports Android's built-in Kotlin). The rest of the app reads downloads as
// DownloadProgress and treats 100% as finished, so the new library's updates must turn
// into exactly that.

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/entities/downloadable.dart';
import 'package:castaway_mobile/services/download/download_manager.dart';
import 'package:castaway_mobile/services/download/mobile_download_manager.dart';

void main() {
  late MobileDownloaderManager manager;
  late List<DownloadProgress> seen;
  final task = DownloadTask(url: 'http://media.example.com/ep.mp3', filename: 'ep.mp3');

  setUp(() {
    manager = MobileDownloaderManager.withoutStarting();
    seen = [];
    manager.downloadProgress.listen(seen.add);
  });
  tearDown(() => manager.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a finished download reports 100% and downloaded', () async {
    manager.onUpdate(TaskStatusUpdate(task, TaskStatus.enqueued));
    manager.onUpdate(TaskStatusUpdate(task, TaskStatus.running));
    manager.onUpdate(TaskProgressUpdate(task, 0.0));
    manager.onUpdate(TaskStatusUpdate(task, TaskStatus.complete));
    await settle();

    expect(seen.first.status, DownloadState.queued);
    expect(seen.map((p) => p.id).toSet(), {task.taskId});
    expect(seen.last.status, DownloadState.downloaded);
    expect(seen.last.percentage, 100);
  });

  test('progress is a percentage, limited to about one update a second', () async {
    manager.onUpdate(TaskProgressUpdate(task, 0.0));
    manager.onUpdate(TaskProgressUpdate(task, 0.25));
    manager.onUpdate(TaskProgressUpdate(task, 0.5));
    await settle();
    expect(seen.map((p) => p.percentage), [0], reason: 'quick updates inside one second are dropped');

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    manager.onUpdate(TaskProgressUpdate(task, 0.756));
    await settle();
    expect(seen.last.percentage, 76);
    expect(seen.last.status, DownloadState.downloading);
  });

  test('a failure keeps the last percentage and reports failed', () async {
    manager.onUpdate(TaskProgressUpdate(task, 0.4));
    manager.onUpdate(TaskStatusUpdate(task, TaskStatus.failed));
    await settle();
    expect(seen.last.status, DownloadState.failed);
    expect(seen.last.percentage, 40);
  });

  test('negative progress (the library signalling a status) is ignored', () async {
    manager.onUpdate(TaskProgressUpdate(task, -1.0));
    await settle();
    expect(seen, isEmpty);
  });

  test('every status maps to the app\'s download states', () async {
    final expected = {
      TaskStatus.enqueued: DownloadState.queued,
      TaskStatus.waitingToRetry: DownloadState.queued,
      TaskStatus.running: DownloadState.downloading,
      TaskStatus.paused: DownloadState.paused,
      TaskStatus.canceled: DownloadState.cancelled,
      TaskStatus.notFound: DownloadState.failed,
      TaskStatus.failed: DownloadState.failed,
      TaskStatus.complete: DownloadState.downloaded,
    };
    for (final entry in expected.entries) {
      manager.onUpdate(TaskStatusUpdate(task, entry.key));
      await settle();
      expect(seen.last.status, entry.value, reason: '${entry.key}');
    }
  });
}
