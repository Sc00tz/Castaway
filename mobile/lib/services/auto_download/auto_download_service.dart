// lib/services/auto_download/auto_download_service.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/entities/podcast.dart';
import 'package:castaway_mobile/services/network/network_status.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/utils/local_download_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoDownloadService {
  static const String _autoDownloadPrefix = 'auto_download_podcast_';
  static const String _lastCheckPrefix = 'auto_download_last_check_';

  /// Called on app launch after auth. Fire-and-forget — does not block startup.
  static Future<void> checkAndDownloadNewEpisodes({
    required BuildContext context,
    required CastawayService castawayService,
    required int userId,
  }) async {
    // Respect the WiFi-only preference for automatic downloads.
    if (context.mounted) {
      final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
      final allowed = await NetworkStatus.canAutoDownload(wifiOnly: settings.autoDownloadWifiOnly);
      if (!allowed) return;
    }

    final prefs = await SharedPreferences.getInstance();

    List<Podcast> podcasts;
    try {
      podcasts = await castawayService.getUserPodcasts(userId);
    } catch (_) {
      return;
    }

    if (podcasts.isEmpty || !context.mounted) return;

    for (final podcast in podcasts) {
      final podcastId = podcast.id;
      if (podcastId == null || podcastId <= 0) continue;
      if (!context.mounted) break;

      final isEnabled = prefs.getBool('$_autoDownloadPrefix$podcastId') ?? false;
      if (!isEnabled) continue;

      await _processOnePodcast(
        context: context,
        castawayService: castawayService,
        userId: userId,
        podcastId: podcastId,
        prefs: prefs,
      );
    }
  }

  static Future<void> _processOnePodcast({
    required BuildContext context,
    required CastawayService castawayService,
    required int userId,
    required int podcastId,
    required SharedPreferences prefs,
  }) async {
    final lastCheckKey = '$_lastCheckPrefix$podcastId';
    final lastCheckStr = prefs.getString(lastCheckKey);
    final lastCheck = lastCheckStr != null ? DateTime.tryParse(lastCheckStr) : null;

    // Record the check time before fetching so concurrent opens don't double-download
    await prefs.setString(lastCheckKey, DateTime.now().toIso8601String());

    // First run — just record the timestamp, don't download the back-catalog
    if (lastCheck == null) return;

    List<CastawayEpisode> episodes;
    try {
      episodes = await castawayService.getPodcastEpisodes(userId, podcastId);
    } catch (_) {
      return;
    }

    if (episodes.isEmpty || !context.mounted) return;

    final newEpisodes = episodes.where((ep) {
      final pubDate = DateTime.tryParse(ep.episodePubDate);
      return pubDate != null && pubDate.isAfter(lastCheck);
    }).toList();

    for (final episode in newEpisodes) {
      if (!context.mounted) break;
      await LocalDownloadUtils.localDownloadEpisode(context, episode);
    }
  }
}
