// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:castaway_mobile/core/environment.dart';
import 'package:castaway_mobile/entities/downloadable.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/download/download_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// A [DownloadManager] for downloading episodes on a phone, on top of
/// background_downloader (which supports Android's built-in Kotlin; the
/// previous flutter_downloader never did).
class MobileDownloaderManager implements DownloadManager {
  final log = Logger('MobileDownloaderManager');
  final downloadController = StreamController<DownloadProgress>();
  final FileDownloader _downloader;
  StreamSubscription<TaskUpdate>? _updates;
  var _lastUpdateTime = 0;

  /// The last percentage reported per task, for status changes that carry none.
  final Map<String, int> _percentages = {};

  @override
  Stream<DownloadProgress> get downloadProgress => downloadController.stream;

  MobileDownloaderManager({FileDownloader? downloader}) : _downloader = downloader ?? FileDownloader() {
    _init();
  }

  /// Without starting the downloader: tests feed [onUpdate] directly.
  @visibleForTesting
  MobileDownloaderManager.withoutStarting() : _downloader = FileDownloader();

  Future<void> _init() async {
    log.fine('Initialising download manager');

    // One episode at a time, as before.
    await _downloader.configure(globalConfig: [(Config.holdingQueue, (1, null, null))]);
    _downloader.configureNotification(
      running: const TaskNotification('{filename}', '{progress}'),
      complete: TaskNotification('{filename}', L.current.downloaded),
      error: TaskNotification('{filename}', L.current.failed_to_download_episode),
      progressBar: true,
    );

    _updates = _downloader.updates.listen(onUpdate);

    // Also delivers what changed while Castaway was closed or in the background.
    await _downloader.start(autoCleanDatabase: true);
  }

  @override
  Future<String?> enqueueTask(String url, String downloadPath, String fileName) async {
    final (baseDirectory, directory, filename) = await Task.split(filePath: '$downloadPath/$fileName');
    final task = DownloadTask(
      url: url,
      filename: filename,
      directory: directory,
      baseDirectory: baseDirectory,
      headers: {'User-Agent': Environment.userAgent()},
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
    );

    if (!await _downloader.enqueue(task)) {
      log.warning('Could not start the download of $url');
      return null;
    }
    return task.taskId;
  }

  /// Stop a download and remove its partial file.
  static Future<void> cancel(String taskId) => FileDownloader().cancelTaskWithId(taskId);

  @override
  void dispose() {
    _updates?.cancel();
    downloadController.close();
  }

  /// Turns the downloader's updates into [DownloadProgress] for the rest of the app,
  /// which treats a download as finished when it reports 100%.
  void onUpdate(TaskUpdate update) {
    final id = update.task.taskId;
    switch (update) {
      case TaskStatusUpdate(:final status):
        if (status == TaskStatus.complete) _percentages[id] = 100;
        _report(id, _percentages[id] ?? 0, _state(status), always: true);
        if (status.isFinalState) _percentages.remove(id);
      case TaskProgressUpdate(:final progress):
        // Negative values signal a status change, which arrives as its own update.
        if (progress < 0) return;
        final percentage = (progress * 100).round().clamp(0, 100);
        _percentages[id] = percentage;
        _report(id, percentage, DownloadState.downloading);
    }
  }

  static DownloadState _state(TaskStatus status) => switch (status) {
        TaskStatus.enqueued || TaskStatus.waitingToRetry => DownloadState.queued,
        TaskStatus.running => DownloadState.downloading,
        TaskStatus.complete => DownloadState.downloaded,
        TaskStatus.canceled => DownloadState.cancelled,
        TaskStatus.paused => DownloadState.paused,
        TaskStatus.failed || TaskStatus.notFound => DownloadState.failed,
      };

  /// Progress is limited to one update a second, so small downloads can't flood
  /// the app; status changes, the start and the end always go through.
  void _report(String id, int percentage, DownloadState state, {bool always = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (always || percentage == 0 || percentage == 100 || now > _lastUpdateTime + 1000) {
      if (!downloadController.isClosed) downloadController.add(DownloadProgress(id, percentage, state));
      _lastUpdateTime = now;
    }
  }
}
