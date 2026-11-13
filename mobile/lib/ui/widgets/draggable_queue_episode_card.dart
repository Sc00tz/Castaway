// lib/ui/widgets/draggable_queue_episode_card.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/ui/widgets/castaway_episode_card.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';

/// A queue row: the standard episode card with a reorder handle in front.
class DraggableQueueEpisodeCard extends StatelessWidget {
  final CastawayEpisode episode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FutureOr<void> Function()? onPlayPressed;
  final int index; // Add index for drag listener

  const DraggableQueueEpisodeCard({
    Key? key,
    required this.episode,
    required this.index,
    this.onTap,
    this.onLongPress,
    this.onPlayPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CastawayEpisodeCard(
      episode: episode,
      onTap: onTap,
      onLongPress: onLongPress,
      onPlayPressed: onPlayPressed,
      leading: ReorderableDragStartListener(
        index: index,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: 24,
            height: 56,
            child: Icon(PhosphorIconsRegular.dotsSixVertical, color: Theme.of(context).hintColor, size: 20),
          ),
        ),
      ),
    );
  }
}
