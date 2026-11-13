// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:castaway_mobile/bloc/podcast/podcast_bloc.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/podcast.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/ui/podcast/podcast_details.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:castaway_mobile/ui/widgets/tile_image.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PodcastGridTile extends StatelessWidget {
  final Podcast podcast;

  const PodcastGridTile({
    super.key,
    required this.podcast,
  });

  @override
  Widget build(BuildContext context) {
    final podcastBloc = Provider.of<PodcastBloc>(context);

    return GestureDetector(
      onTap: () async {
        await _navigateToPodcastDetails(context, podcastBloc);
      },
      child: Semantics(
        label: podcast.title,
        child: GridTile(
          child: Hero(
            key: Key('tilehero${podcast.imageUrl}:${podcast.link}'),
            tag: '${podcast.imageUrl}:${podcast.link}',
            child: TileImage(
              url: podcast.imageUrl!,
              size: 18.0,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToPodcastDetails(BuildContext context, PodcastBloc podcastBloc) async {
    // Check if this is a Castaway setup and if the podcast is already subscribed
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    
    if (settings.castawayServer != null && 
        settings.castawayApiKey != null && 
        settings.castawayUserId != null) {
      
      // Check if podcast is already subscribed
      final castawayService = CastawayService();
      castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
      
      try {
        final isSubscribed = await castawayService.checkPodcastExists(
          podcast.title, 
          podcast.url!, 
          settings.castawayUserId!
        );
        
        if (isSubscribed) {
          // Get the internal Castaway database ID
          final internalPodcastId = await castawayService.getPodcastId(
            settings.castawayUserId!,
            podcast.url!,
            podcast.title
          );
          
          // Use Castaway podcast details for subscribed podcasts
          final unifiedPodcast = UnifiedCastawayPodcast(
            id: internalPodcastId ?? 0,
            indexId: 0, // Default for subscribed podcasts
            title: podcast.title,
            url: podcast.url ?? '',
            originalUrl: podcast.url ?? '',
            link: podcast.link ?? '',
            description: podcast.description ?? '',
            author: podcast.copyright ?? '',
            ownerName: podcast.copyright ?? '',
            image: podcast.imageUrl ?? '',
            artwork: podcast.imageUrl ?? '',
            lastUpdateTime: 0,
            explicit: false,
            episodeCount: 0, // Will be loaded
          );
          
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'castawaypodcastdetails'),
                builder: (context) => CastawayPodcastDetails(
                  podcast: unifiedPodcast,
                  isFollowing: true,
                ),
              ),
            );
          }
          return;
        }
      } catch (e) {
        // If check fails, fall through to standard podcast details
        print('Error checking subscription status: $e');
      }
    }
    
    // Use standard podcast details for non-subscribed or non-Castaway setups
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'podcastdetails'),
          builder: (context) => PodcastDetails(podcast, podcastBloc),
        ),
      );
    }
  }
}

class PodcastTitledGridTile extends StatelessWidget {
  final Podcast podcast;

  const PodcastTitledGridTile({
    super.key,
    required this.podcast,
  });

  @override
  Widget build(BuildContext context) {
    final podcastBloc = Provider.of<PodcastBloc>(context);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () async {
        await _navigateToPodcastDetails(context, podcastBloc);
      },
      child: GridTile(
        child: Hero(
          key: Key('tilehero${podcast.imageUrl}:${podcast.link}'),
          tag: '${podcast.imageUrl}:${podcast.link}',
          child: Column(
            children: [
              TileImage(
                url: podcast.imageUrl!,
                size: 128.0,
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: 4.0,
                ),
                child: Text(
                  podcast.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToPodcastDetails(BuildContext context, PodcastBloc podcastBloc) async {
    // Check if this is a Castaway setup and if the podcast is already subscribed
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final settings = settingsBloc.currentSettings;
    
    if (settings.castawayServer != null && 
        settings.castawayApiKey != null && 
        settings.castawayUserId != null) {
      
      // Check if podcast is already subscribed
      final castawayService = CastawayService();
      castawayService.setCredentials(settings.castawayServer!, settings.castawayApiKey!);
      
      try {
        final isSubscribed = await castawayService.checkPodcastExists(
          podcast.title, 
          podcast.url!, 
          settings.castawayUserId!
        );
        
        if (isSubscribed) {
          // Get the internal Castaway database ID
          final internalPodcastId = await castawayService.getPodcastId(
            settings.castawayUserId!,
            podcast.url!,
            podcast.title
          );
          
          // Use Castaway podcast details for subscribed podcasts
          final unifiedPodcast = UnifiedCastawayPodcast(
            id: internalPodcastId ?? 0,
            indexId: 0, // Default for subscribed podcasts
            title: podcast.title,
            url: podcast.url ?? '',
            originalUrl: podcast.url ?? '',
            link: podcast.link ?? '',
            description: podcast.description ?? '',
            author: podcast.copyright ?? '',
            ownerName: podcast.copyright ?? '',
            image: podcast.imageUrl ?? '',
            artwork: podcast.imageUrl ?? '',
            lastUpdateTime: 0,
            explicit: false,
            episodeCount: 0, // Will be loaded
          );
          
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'castawaypodcastdetails'),
                builder: (context) => CastawayPodcastDetails(
                  podcast: unifiedPodcast,
                  isFollowing: true,
                ),
              ),
            );
          }
          return;
        }
      } catch (e) {
        // If check fails, fall through to standard podcast details
        print('Error checking subscription status: $e');
      }
    }
    
    // Use standard podcast details for non-subscribed or non-Castaway setups
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'podcastdetails'),
          builder: (context) => PodcastDetails(podcast, podcastBloc),
        ),
      );
    }
  }
}
