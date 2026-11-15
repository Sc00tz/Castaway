// lib/ui/widgets/podcast_result_card.dart
//
// A show from a directory (search results, Discover): artwork, title, author, a line of the
// description, and a follow button. Tapping it opens the show.

import 'package:flutter/material.dart';
import 'package:castaway_mobile/core/html_text.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/ui/widgets/lazy_network_image.dart';
import 'package:castaway_mobile/ui/widgets/soft_ui.dart';

class PodcastResultCard extends StatelessWidget {
  final UnifiedCastawayPodcast podcast;
  final bool isAdded;
  final VoidCallback onToggle;

  /// Called when the show is followed or unfollowed from its own page.
  final ValueChanged<bool> onFollowChanged;

  const PodcastResultCard({
    super.key,
    required this.podcast,
    required this.isAdded,
    required this.onToggle,
    required this.onFollowChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context)!;
    final meta = [
      if (podcast.episodeCount > 0) l.episodes_count(podcast.episodeCount),
      if (podcast.explicit) l.explicit,
    ].join('  ·  ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CastawayPodcastDetails(
                podcast: podcast,
                isFollowing: isAdded,
                onFollowChanged: onFollowChanged,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LazyNetworkImage(
                imageUrl: podcast.artwork,
                width: 72,
                height: 72,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      podcast.title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (podcast.author.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        podcast.author,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.primaryColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (podcast.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        htmlToPlainText(podcast.description),
                        style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(meta, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CircleAction(
                size: 40,
                tooltip: isAdded ? l.unfollow_label : l.subscribe_label,
                onTap: onToggle,
                icon: Icon(
                  isAdded ? PhosphorIconsBold.check : PhosphorIconsBold.plus,
                  size: 18,
                  color: isAdded ? theme.primaryColor : softNeutral(theme).withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
