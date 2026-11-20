// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:castaway_mobile/bloc/podcast/audio_bloc.dart';
import 'package:castaway_mobile/entities/episode.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/audio/audio_player_service.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/ui/podcast/now_playing.dart';
import 'package:castaway_mobile/ui/podcast/skip_interval_icon.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';
import 'package:castaway_mobile/ui/widgets/placeholder_builder.dart';
import 'package:castaway_mobile/ui/widgets/podcast_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';

/// Displays a mini podcast player widget if a podcast is playing or paused.
///
/// If stopped a zero height box is built instead. Tapping on the mini player
/// will open the main player window.
///
/// The app shell builds one instance outside the tab navigator, so it stays
/// mounted while pages are pushed and popped above it.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
  });

  static bool _isVisible(AudioState? state, Episode? episode) {
    if (episode == null) return false;
    return state != null && state != AudioState.stopped && state != AudioState.none;
  }

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    return StreamBuilder<AudioState>(
        stream: audioBloc.playingState,
        initialData: audioBloc.playingState?.valueOrNull,
        builder: (context, snapshot) {
          final active = _isVisible(snapshot.data, audioBloc.nowPlaying?.valueOrNull);
          return AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: active
                ? const Material(type: MaterialType.transparency, child: _MiniPlayerBody())
                : const SizedBox(width: double.infinity),
          );
        });
  }
}

class _MiniPlayerBody extends StatelessWidget {
  const _MiniPlayerBody();

  void _openNowPlaying(BuildContext context) => showNowPlaying(context);

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
    final placeholderBuilder = PlaceholderBuilder.of(context);
    final fallbackImage = const Image(image: AssetImage('assets/images/favicon.png'));
    final l = L.of(context)!;

    return StreamBuilder<Episode?>(
        stream: audioBloc.nowPlaying,
        initialData: audioBloc.nowPlaying?.valueOrNull,
        builder: (context, snapshot) {
          final episode = snapshot.data;
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Dismissible(
              key: ValueKey('mini-${episode?.guid}'),
              confirmDismiss: (direction) async {
                audioBloc.transitionState(TransitionState.stop);
                return true;
              },
              direction: DismissDirection.startToEnd,
              child: GestureDetector(
                key: const Key('miniplayergesture'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openNowPlaying(context),
                child: Semantics(
                  header: true,
                  label: l.semantics_mini_player_header,
                  child: Container(
                    height: 64,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: style.surfaceHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _ProgressLine(audioBloc: audioBloc),
                        Expanded(
                          child: StreamBuilder<AudioState>(
                              stream: audioBloc.playingState,
                              initialData: audioBloc.playingState?.valueOrNull,
                              builder: (context, stateSnapshot) {
                                final state = stateSnapshot.data;
                                final playing = state == AudioState.playing;
                                final loading = state == AudioState.buffering || state == AudioState.starting;
                                final failed = state == AudioState.error;

                                return Row(
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
                                      child: ExcludeSemantics(
                                        child: SizedBox(
                                          height: 44,
                                          width: 44,
                                          child: episode?.imageUrl != null
                                              ? PodcastImage(
                                                  key: Key('mini${episode!.imageUrl}'),
                                                  url: episode.imageUrl!,
                                                  width: 44,
                                                  height: 44,
                                                  borderRadius: 8.0,
                                                  placeholder: placeholderBuilder?.builder()(context) ?? fallbackImage,
                                                  errorPlaceholder:
                                                      placeholderBuilder?.errorBuilder()(context) ?? fallbackImage,
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            episode?.title ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: style.text,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            failed ? l.mini_player_failed : episode?.podcast ?? episode?.author ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: failed
                                                  ? Theme.of(context).colorScheme.error
                                                  : readableOn(style.muted, style.surfaceHigh),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!failed)
                                      _MiniButton(
                                        tooltip: l.rewind_button_label,
                                        onPressed: () => audioBloc.transitionState(TransitionState.rewind),
                                        child: SkipIntervalIcon(
                                          icon: PhosphorIconsRegular.arrowCounterClockwise,
                                          seconds: settings.rewindInterval,
                                          size: 28,
                                          color: style.text,
                                        ),
                                      ),
                                    SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 180),
                                        child: loading
                                            ? Padding(
                                                key: const ValueKey('loading'),
                                                padding: const EdgeInsets.all(11),
                                                child: CircularProgressIndicator(strokeWidth: 2.4, color: style.accent),
                                              )
                                            : Material(
                                                key: ValueKey(failed ? 'retry' : playing),
                                                color: style.accent,
                                                shape: const CircleBorder(),
                                                child: InkWell(
                                                  key: const Key('miniplayer-play'),
                                                  customBorder: const CircleBorder(),
                                                  onTap: () => audioBloc.transitionState(
                                                    playing ? TransitionState.pause : TransitionState.play,
                                                  ),
                                                  child: Center(
                                                    child: Icon(
                                                      failed
                                                          ? PhosphorIconsBold.arrowClockwise
                                                          : playing
                                                              ? PhosphorIconsFill.pause
                                                              : PhosphorIconsFill.play,
                                                      size: 20,
                                                      color: style.onAccent,
                                                      semanticLabel: playing ? l.pause_button_label : l.play_button_label,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                    if (!failed)
                                      _MiniButton(
                                        tooltip: l.fast_forward_button_label,
                                        onPressed: () => audioBloc.transitionState(TransitionState.fastforward),
                                        child: SkipIntervalIcon(
                                          icon: PhosphorIconsRegular.arrowClockwise,
                                          seconds: settings.fastForwardInterval,
                                          size: 28,
                                          color: style.text,
                                        ),
                                      ),
                                    _MiniButton(
                                      key: const Key('miniplayer-upnext'),
                                      tooltip: l.up_next_queue_label,
                                      onPressed: () => showUpNextSheet(context),
                                      child: Icon(PhosphorIconsRegular.queue, size: 22, color: style.text),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                );
                              }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        });
  }
}

class _MiniButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  const _MiniButton({super.key, required this.tooltip, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkResponse(
          radius: 22,
          onTap: onPressed,
          child: SizedBox(width: 44, height: 48, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final AudioBloc audioBloc;

  const _ProgressLine({required this.audioBloc});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionState>(
        stream: audioBloc.playPosition,
        initialData: audioBloc.playPosition?.valueOrNull,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final length = data?.length.inMilliseconds ?? 0;
          final fraction = length > 0 ? (data!.position.inMilliseconds / length).clamp(0.0, 1.0) : 0.0;
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(height: 3.0, color: CastawayStyle.of(context).accent),
            ),
          );
        });
  }
}
