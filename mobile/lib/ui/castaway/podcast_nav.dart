// lib/ui/castaway/podcast_nav.dart
import 'package:flutter/material.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:provider/provider.dart';

/// Navigates to the podcast details page given only a podcast id.
///
/// Fetches the podcast metadata via [CastawayService.getPodcastDetailsById]
/// and pushes [CastawayPodcastDetails]. Shows a SnackBar on any error.
/// [fallbackTitle] and [fallbackArtwork] are used when the fetched details
/// don't provide them (e.g. from an episode we already have on hand).
Future<void> navigateToPodcastById(
  BuildContext context,
  int? podcastId, {
  String? fallbackTitle,
  String? fallbackArtwork,
}) async {
  void showError(String message, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  if (podcastId == null || podcastId <= 0) {
    showError('Podcast not available', Colors.orange);
    return;
  }

  try {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    final userId = settings.castawayUserId;

    if (userId == null ||
        settings.castawayServer == null ||
        settings.castawayApiKey == null) {
      showError('Not logged in', Colors.red);
      return;
    }

    // CastawayService is not a singleton, so a fresh instance has no
    // credentials — set them before making the call.
    final service = CastawayService()
      ..setCredentials(settings.castawayServer!, settings.castawayApiKey!);
    final podcastDetails =
        await service.getPodcastDetailsById(podcastId, userId);

    if (!context.mounted) return;

    final podcast = UnifiedCastawayPodcast(
      id: podcastId,
      indexId: 0,
      title: podcastDetails?['podcastname'] ?? fallbackTitle ?? '',
      url: podcastDetails?['feedurl'] ?? '',
      originalUrl: podcastDetails?['feedurl'] ?? '',
      link: podcastDetails?['websiteurl'] ?? '',
      description: podcastDetails?['description'] ?? '',
      author: podcastDetails?['author'] ?? '',
      ownerName: podcastDetails?['author'] ?? '',
      image: podcastDetails?['artworkurl'] ?? fallbackArtwork ?? '',
      artwork: podcastDetails?['artworkurl'] ?? fallbackArtwork ?? '',
      lastUpdateTime: 0,
      explicit: podcastDetails?['explicit'] ?? false,
      episodeCount: podcastDetails?['episodecount'] ?? 0,
    );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'castaway_podcast_details'),
        builder: (context) => CastawayPodcastDetails(
          podcast: podcast,
          isFollowing: true, // Assume following since we have a podcast ID
        ),
      ),
    );
  } catch (e) {
    showError('Error navigating to podcast: $e', Colors.red);
  }
}
