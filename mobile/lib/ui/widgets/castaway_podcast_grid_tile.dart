// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:castaway_mobile/entities/podcast.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:castaway_mobile/ui/widgets/tile_image.dart';
import 'package:castaway_mobile/ui/widgets/podcast_image.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:flutter/material.dart';

class CastawayPodcastGridTile extends StatelessWidget {
  final Podcast podcast;

  const CastawayPodcastGridTile({
    super.key,
    required this.podcast,
  });

  UnifiedCastawayPodcast _convertToUnifiedPodcast() {
    return UnifiedCastawayPodcast(
      id: podcast.id ?? 0,
      indexId: 0, // Default value for subscribed podcasts
      title: podcast.title,
      url: podcast.url,
      originalUrl: podcast.url,
      link: podcast.link ?? '',
      description: podcast.description ?? '',
      author: podcast.copyright ?? '',
      ownerName: podcast.copyright ?? '',
      image: podcast.imageUrl ?? '',
      artwork: podcast.imageUrl ?? '',
      lastUpdateTime: 0, // Default value
      categories: null,
      explicit: false, // Default value
      episodeCount: podcast.episodes.length, // Use actual episode count
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final unifiedPodcast = _convertToUnifiedPodcast();
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'castaway_podcast_details'),
            builder: (context) => CastawayPodcastDetails(
              podcast: unifiedPodcast,
              isFollowing: true, // These are subscribed podcasts
            ),
          ),
        );
      },
      child: Semantics(
        button: true,
        label: podcast.newEpisodeCount > 0
            ? L.of(context)!.podcast_new_episodes_semantics(podcast.title, podcast.newEpisodeCount)
            : podcast.title,
        excludeSemantics: true,
        child: LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          return Stack(
            children: [
              KeyedSubtree(
                key: Key('tilehero${podcast.imageUrl}:${podcast.link}'),
                child: PodcastImage(
                  key: Key('tile${podcast.imageUrl}'),
                  url: podcast.imageUrl ?? '',
                  width: size,
                  height: size,
                  borderRadius: 10.0,
                  fit: BoxFit.cover,
                  placeholder: const Image(image: AssetImage('assets/images/favicon.png')),
                  errorPlaceholder: const Image(image: AssetImage('assets/images/favicon.png')),
                ),
              ),
              if (podcast.newEpisodeCount > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    key: ValueKey('new-badge-${podcast.id}'),
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: castawayNavy,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      podcast.newEpisodeCount > 99 ? '99+' : '${podcast.newEpisodeCount}', // i18n-ignore
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class CastawayPodcastTitledGridTile extends StatelessWidget {
  final Podcast podcast;

  const CastawayPodcastTitledGridTile({
    super.key,
    required this.podcast,
  });

  UnifiedCastawayPodcast _convertToUnifiedPodcast() {
    return UnifiedCastawayPodcast(
      id: podcast.id ?? 0,
      indexId: 0, // Default value for subscribed podcasts
      title: podcast.title,
      url: podcast.url,
      originalUrl: podcast.url,
      link: podcast.link ?? '',
      description: podcast.description ?? '',
      author: podcast.copyright ?? '',
      ownerName: podcast.copyright ?? '',
      image: podcast.imageUrl ?? '',
      artwork: podcast.imageUrl ?? '',
      lastUpdateTime: 0, // Default value
      categories: null,
      explicit: false, // Default value
      episodeCount: podcast.episodes.length, // Use actual episode count
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        final unifiedPodcast = _convertToUnifiedPodcast();
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'castaway_podcast_details'),
            builder: (context) => CastawayPodcastDetails(
              podcast: unifiedPodcast,
              isFollowing: true, // These are subscribed podcasts
            ),
          ),
        );
      },
      child: GridTile(
        child: KeyedSubtree(
          key: Key('tilehero${podcast.imageUrl}:${podcast.link}'),
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
}