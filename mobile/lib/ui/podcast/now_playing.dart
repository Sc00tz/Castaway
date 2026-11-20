// The full-screen player, opened from the mini player.
//
// Layout (2026-11 redesign, Pocket Casts-style): artwork, chapter navigation,
// title and podcast, scrub bar, skip back / play / skip forward, and an action
// bar (Up Next, speed, transcript, other devices, save, sleep). Chapters, Up
// Next and the episode notes share one sheet with tabs. Each part listens only
// to the stream it shows, so a position tick repaints the scrub bar and
// nothing else.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:castaway_mobile/bloc/podcast/audio_bloc.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/chapter.dart';
import 'package:castaway_mobile/entities/episode.dart';
import 'package:castaway_mobile/entities/pending_action.dart';
import 'package:castaway_mobile/entities/sleep.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/audio/audio_player_service.dart';
import 'package:castaway_mobile/services/global_services.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/podcast/podcast_service.dart';
import 'package:castaway_mobile/entities/transcript.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/ui/castaway/podcast_nav.dart';
import 'package:castaway_mobile/ui/podcast/person_avatar.dart';
import 'package:castaway_mobile/ui/podcast/castaway_up_next_view.dart';
import 'package:castaway_mobile/ui/podcast/playback_error_listener.dart';
import 'package:castaway_mobile/ui/podcast/remote_devices_button.dart';
import 'package:castaway_mobile/ui/podcast/skip_interval_icon.dart';
import 'package:castaway_mobile/ui/tab_navigator.dart';
import 'package:castaway_mobile/ui/utils/artwork_colors.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';
import 'package:castaway_mobile/ui/widgets/placeholder_builder.dart';
import 'package:castaway_mobile/ui/widgets/podcast_html.dart';
import 'package:castaway_mobile/ui/widgets/podcast_image.dart';
import 'package:castaway_mobile/ui/widgets/sleep_selector.dart';
import 'package:castaway_mobile/ui/widgets/soft_ui.dart';
import 'package:castaway_mobile/ui/widgets/speed_selector.dart';
import 'package:provider/provider.dart';

/// Opens the full-screen player above the app shell. Swipe down to close.
Future<void> showNowPlaying(BuildContext context) {
  // A modal sheet's content gets no top safe-area inset, so take the status
  // bar height from the screen opening it (or the window as a fallback).
  final view = View.of(context);
  final topInset = math.max(MediaQuery.paddingOf(context).top, view.padding.top / view.devicePixelRatio);

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    routeSettings: const RouteSettings(name: 'nowplaying'),
    builder: (_) => NowPlaying(topInset: topInset),
  );
}

class NowPlaying extends StatefulWidget {
  /// Height of the status bar area the player draws behind.
  final double topInset;

  const NowPlaying({super.key, this.topInset = 0});

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  StreamSubscription<AudioState>? _stoppedSubscription;
  String? _artUrl;
  Color? _artColor;

  @override
  void initState() {
    super.initState();
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    // Close once nothing is playing any more.
    _stoppedSubscription = audioBloc.playingState!.where((s) => s == AudioState.stopped).take(1).listen((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _stoppedSubscription?.cancel();
    super.dispose();
  }

  bool get _artworkAccent =>
      Provider.of<SettingsBloc>(context, listen: false).currentSettings.artworkAccentColors;

  /// Artwork-derived accent when that setting is on, else the theme's (orange
  /// in the Castaway themes).
  Color _accent(ThemeData theme, Episode episode) {
    final themeAccent = CastawayStyle.fromTheme(theme).accent;
    if (!_artworkAccent) return themeAccent;

    final url = episode.imageUrl;
    if (url != null && url.isNotEmpty && url != _artUrl) {
      _artUrl = url;
      final brightness = ThemeData.estimateBrightnessForColor(theme.scaffoldBackgroundColor);
      _artColor = ArtworkColors.cached(url, null, brightness);
      if (_artColor == null) {
        ArtworkColors.resolve(url, null, brightness).then((color) {
          if (mounted && color != null && url == _artUrl) setState(() => _artColor = color);
        });
      }
    }
    return _artColor ?? themeAccent;
  }

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final theme = Theme.of(context);

    return Semantics(
      label: L.of(context)!.semantics_main_player_header,
      explicitChildNodes: true,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: StreamBuilder<Episode?>(
          stream: audioBloc.nowPlaying,
          initialData: audioBloc.nowPlaying?.valueOrNull,
          builder: (context, snapshot) {
            final episode = snapshot.data;
            if (episode == null) return const SizedBox.shrink();

            // Eases between colours when the episode changes.
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: _accent(theme, episode)),
              duration: const Duration(milliseconds: 350),
              builder: (context, accent, _) => _PlayerSurface(
                episode: episode,
                accent: accent!,
                tinted: _artworkAccent,
                topInset: widget.topInset,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlayerSurface extends StatelessWidget {
  final Episode episode;
  final Color accent;

  /// Wash the top of the player in [accent] (only with artwork colours on).
  final bool tinted;
  final double topInset;

  const _PlayerSurface({required this.episode, required this.accent, required this.tinted, required this.topInset});

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return PlaybackErrorListener(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            gradient: tinted
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.alphaBlend(accent.withOpacity(0.22), bg), bg],
                    stops: const [0.0, 0.6],
                  )
                : null,
          ),
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.only(top: topInset),
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > constraints.maxHeight && constraints.maxWidth >= 600;
              final controls = <Widget>[
                _ChapterNav(episode: episode),
                _TitleBlock(episode: episode, accent: accent),
                const SizedBox(height: 14),
                _ScrubBar(episode: episode, accent: accent),
                const SizedBox(height: 4),
                _Transport(accent: accent),
                const SizedBox(height: 18),
                _ActionBar(episode: episode, accent: accent),
              ];

              if (wide) {
                return Column(
                  children: [
                    _Header(episode: episode),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(32, 8, 16, 24),
                              child: _Artwork(episode: episode),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 32, 16),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: controls),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  _Header(episode: episode),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 12, 40, 20),
                      child: _Artwork(episode: episode),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Column(children: controls),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Close the player and open the playing episode's podcast in the app.
void _goToPodcast(BuildContext context, Episode episode) {
  final podcastId = GlobalServices.castawayAudioService?.currentPodcastId;
  Navigator.of(context).maybePop();
  final appContext = tabNavigatorKey.currentContext;
  if (appContext == null) return;
  navigateToPodcastById(
    appContext,
    podcastId,
    fallbackTitle: episode.podcast,
    fallbackArtwork: episode.imageUrl,
  );
}

class _Header extends StatelessWidget {
  final Episode episode;

  const _Header({required this.episode});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: L.of(context)!.minimise_player_window_button_label,
            icon: Icon(PhosphorIconsRegular.caretDown, color: style.text, size: 26),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: style.surfaceHigh, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: L.of(context)!.more_label,
            icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: style.text, size: 26),
            onSelected: (value) {
              switch (value) {
                case 'notes':
                  _showPlayerSheet(context, _PlayerSheetTab.notes);
                case 'podcast':
                  _goToPodcast(context, episode);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'notes', child: Text(L.of(context)!.notes_label)),
              PopupMenuItem(value: 'podcast', child: Text(L.of(context)!.go_to_podcast)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final Episode episode;

  const _Artwork({required this.episode});

  @override
  Widget build(BuildContext context) {
    final placeholderBuilder = PlaceholderBuilder.of(context);
    const fallback = Image(image: AssetImage('assets/images/favicon.png'));
    // Chapter artwork replaces the episode's while that chapter plays.
    final url = episode.positionalImageUrl;

    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest.shortestSide;
      return Center(
        child: Semantics(
          label: L.of(context)!.semantic_podcast_artwork_label,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.30), blurRadius: 32, offset: const Offset(0, 14)),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: url == null || url.isEmpty
                  ? SizedBox(
                      key: const ValueKey('no-art'),
                      width: size,
                      height: size,
                      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: fallback),
                    )
                  : PodcastImage(
                      key: ValueKey('nowplaying$url'),
                      url: url,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      borderRadius: 14,
                      placeholder: placeholderBuilder?.builder()(context) ?? fallback,
                      errorPlaceholder: placeholderBuilder?.errorBuilder()(context) ?? fallback,
                    ),
            ),
          ),
        ),
      );
    });
  }
}

/// "‹  Chapter title / Chapter 3 of 9  ›" above the episode title, when the
/// episode has more than one chapter. Tapping the title opens the chapters.
class _ChapterNav extends StatelessWidget {
  final Episode episode;

  const _ChapterNav({required this.episode});

  /// Seek to the previous chapter, or back to the start of this one if it has
  /// been playing for more than a few seconds.
  void _previousChapter(AudioBloc audioBloc, List<Chapter> chapters) {
    final position = audioBloc.playPosition?.valueOrNull?.position.inMilliseconds ?? 0;
    final seconds = position / 1000;
    final current = chapters.lastIndexWhere((c) => c.startTime <= seconds);
    if (current < 0) return;
    final target = seconds - chapters[current].startTime > 3 || current == 0 ? current : current - 1;
    audioBloc.transitionPosition(chapters[target].startTime);
  }

  void _nextChapter(AudioBloc audioBloc, List<Chapter> chapters) {
    final position = audioBloc.playPosition?.valueOrNull?.position.inMilliseconds ?? 0;
    final next = chapters.indexWhere((c) => c.startTime > position / 1000);
    if (next >= 0) audioBloc.transitionPosition(chapters[next].startTime);
  }

  @override
  Widget build(BuildContext context) {
    final chapters = _tocChapters(episode);
    if (chapters.length < 2) return const SizedBox(height: 4);

    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final style = CastawayStyle.of(context);
    final l = L.of(context)!;
    final current = chapters.indexWhere((c) => c == episode.currentChapter);
    final title = current >= 0 ? chapters[current].title.trim() : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          IconButton(
            tooltip: l.previous_chapter,
            color: style.muted,
            icon: const Icon(PhosphorIconsFill.skipBack, size: 20),
            onPressed: () => _previousChapter(audioBloc, chapters),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showPlayerSheet(context, _PlayerSheetTab.chapters),
              child: Semantics(
                button: true,
                label: '${l.semantic_current_chapter_label} $title',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: style.text),
                      ),
                      if (current >= 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          l.chapter_x_of_y(current + 1, chapters.length),
                          style: TextStyle(fontSize: 12, color: style.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l.next_chapter,
            color: style.muted,
            icon: const Icon(PhosphorIconsFill.skipForward, size: 20),
            onPressed: () => _nextChapter(audioBloc, chapters),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  final Episode episode;
  final Color accent;

  const _TitleBlock({required this.episode, required this.accent});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    final podcast = episode.podcast ?? '';

    return Column(
      children: [
        Semantics(
          container: true,
          child: Text(
            episode.title ?? '',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.25, color: style.text),
          ),
        ),
        if (podcast.isNotEmpty) ...[
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _goToPodcast(context, episode),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                podcast,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: readableOn(accent, style.background),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _formatTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Chapters shown in the table of contents, in order.
List<Chapter> _tocChapters(Episode episode) => episode.chapters.where((c) => c.toc).toList();

/// Scrub bar with the buffered range and chapter boundaries. Drag or tap to seek.
class _ScrubBar extends StatefulWidget {
  final Episode episode;
  final Color accent;

  const _ScrubBar({required this.episode, required this.accent});

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  /// Where the finger is while dragging, as a fraction of the episode.
  double? _dragFraction;

  void _seekTo(AudioBloc audioBloc, double fraction, Duration length) {
    audioBloc.transitionPosition(length.inMilliseconds * fraction / 1000);
  }

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final theme = Theme.of(context);
    final style = CastawayStyle.of(context);
    final labels = TextStyle(
      fontSize: 12,
      color: style.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return StreamBuilder<PositionState>(
      stream: audioBloc.playPosition,
      initialData: audioBloc.playPosition?.valueOrNull,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final length = data?.length ?? Duration.zero;
        final lengthMs = length.inMilliseconds;
        final canSeek = lengthMs > 0;
        double fractionOf(Duration d) => canSeek ? (d.inMilliseconds / lengthMs).clamp(0.0, 1.0) : 0.0;

        final fraction = _dragFraction ?? fractionOf(data?.position ?? Duration.zero);
        final shown = Duration(milliseconds: (lengthMs * fraction).round());
        final remaining = length - shown;
        final chapterMarks = canSeek
            ? _tocChapters(widget.episode)
                .map((c) => c.startTime * 1000 / lengthMs)
                .where((f) => f > 0 && f < 1)
                .toList()
            : const <double>[];

        final skips = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
        Duration clamp(Duration d) => d < Duration.zero ? Duration.zero : (d > length ? length : d);

        return Semantics(
          slider: true,
          label: L.of(context)!.now_playing_episode_position,
          value: _formatTime(shown),
          // Flutter requires these alongside onIncrease / onDecrease.
          increasedValue: _formatTime(clamp(shown + Duration(seconds: skips.fastForwardInterval))),
          decreasedValue: _formatTime(clamp(shown - Duration(seconds: skips.rewindInterval))),
          onIncrease: canSeek ? () => audioBloc.transitionState(TransitionState.fastforward) : null,
          onDecrease: canSeek ? () => audioBloc.transitionState(TransitionState.rewind) : null,
          child: Column(
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth;
                double at(Offset p) => (p.dx / width).clamp(0.0, 1.0);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: canSeek
                      ? (d) {
                          HapticFeedback.selectionClick();
                          setState(() => _dragFraction = at(d.localPosition));
                        }
                      : null,
                  onHorizontalDragUpdate: canSeek ? (d) => setState(() => _dragFraction = at(d.localPosition)) : null,
                  onHorizontalDragEnd: canSeek
                      ? (_) {
                          _seekTo(audioBloc, _dragFraction ?? fraction, length);
                          setState(() => _dragFraction = null);
                        }
                      : null,
                  onHorizontalDragCancel: () => setState(() => _dragFraction = null),
                  onTapUp: canSeek ? (d) => _seekTo(audioBloc, at(d.localPosition), length) : null,
                  child: SizedBox(
                    height: 32,
                    width: width,
                    child: CustomPaint(
                      painter: _ScrubPainter(
                        played: fraction,
                        buffered: fractionOf(data?.buffered ?? Duration.zero),
                        chapterMarks: chapterMarks,
                        dragging: _dragFraction != null,
                        accent: widget.accent,
                        thumb: style.text,
                        track: style.surfaceHigh,
                        bufferedColor: Color.alphaBlend(style.text.withOpacity(0.12), style.surfaceHigh),
                        gap: theme.scaffoldBackgroundColor,
                      ),
                    ),
                  ),
                );
              }),
              Row(
                children: [
                  Text(_formatTime(shown), style: labels),
                  const Spacer(),
                  Text(
                    '−${_formatTime(remaining.isNegative ? Duration.zero : remaining)}',
                    semanticsLabel: '${L.of(context)!.now_playing_episode_time_remaining} ${_formatTime(remaining)}',
                    style: labels,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScrubPainter extends CustomPainter {
  final double played;
  final double buffered;
  final List<double> chapterMarks;

  final bool dragging;
  final Color accent;
  final Color thumb;
  final Color track;
  final Color bufferedColor;
  final Color gap;

  _ScrubPainter({
    required this.played,
    required this.buffered,
    required this.chapterMarks,
    required this.dragging,
    required this.accent,
    required this.thumb,
    required this.track,
    required this.bufferedColor,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final height = dragging ? 7.0 : 4.0;
    final top = (size.height - height) / 2;
    final radius = Radius.circular(height / 2);
    RRect bar(double from, double to) =>
        RRect.fromLTRBR(size.width * from, top, size.width * to, top + height, radius);

    canvas.drawRRect(bar(0, 1), Paint()..color = track);
    if (buffered > played) canvas.drawRRect(bar(0, buffered), Paint()..color = bufferedColor);
    canvas.drawRRect(bar(0, played), Paint()..color = accent);

    // Chapter boundaries as small gaps in the bar.
    final gapPaint = Paint()..color = gap;
    for (final mark in chapterMarks) {
      final x = size.width * mark;
      canvas.drawRect(Rect.fromLTWH(x - 1, top, 2, height), gapPaint);
    }

    canvas.drawCircle(
      Offset(size.width * played, size.height / 2),
      dragging ? 10 : 8,
      Paint()..color = thumb,
    );
  }

  @override
  bool shouldRepaint(_ScrubPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.dragging != dragging ||
      old.accent != accent ||
      old.thumb != thumb ||
      old.track != track ||
      old.chapterMarks.length != chapterMarks.length;
}

class _Transport extends StatelessWidget {
  final Color accent;

  const _Transport({required this.accent});

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SkipButton(
          icon: PhosphorIconsRegular.arrowCounterClockwise,
          seconds: settings.rewindInterval,
          tooltip: L.of(context)!.rewind_button_label,
          onTap: () => audioBloc.transitionState(TransitionState.rewind),
        ),
        const SizedBox(width: 28),
        _PlayButton(accent: accent),
        const SizedBox(width: 28),
        _SkipButton(
          icon: PhosphorIconsRegular.arrowClockwise,
          seconds: settings.fastForwardInterval,
          tooltip: L.of(context)!.fast_forward_button_label,
          onTap: () => audioBloc.transitionState(TransitionState.fastforward),
        ),
      ],
    );
  }
}

/// Rewind / fast-forward with the interval written inside the arrow.
class _SkipButton extends StatelessWidget {
  final IconData icon;
  final int seconds;
  final String tooltip;
  final VoidCallback onTap;

  const _SkipButton({required this.icon, required this.seconds, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 36,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: 68,
          height: 68,
          child: Center(
            child: SkipIntervalIcon(icon: icon, seconds: seconds, size: 50, color: style.text, semanticLabel: tooltip),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final Color accent;

  const _PlayButton({required this.accent});

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final fg = inkOn(accent);

    return StreamBuilder<AudioState>(
      stream: audioBloc.playingState,
      initialData: audioBloc.playingState?.valueOrNull,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state == AudioState.playing;
        final loading = state == AudioState.buffering || state == AudioState.starting;
        final failed = state == AudioState.error;
        final label = playing ? L.of(context)!.pause_button_label : L.of(context)!.play_button_label;

        return SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(strokeWidth: 3, color: accent),
                ),
              Material(
                color: accent,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  key: const Key('nowplaying-play'),
                  customBorder: const CircleBorder(),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    audioBloc.transitionState(playing ? TransitionState.pause : TransitionState.play);
                  },
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: Icon(
                      failed
                          ? PhosphorIconsBold.arrowClockwise
                          : playing
                              ? PhosphorIconsFill.pause
                              : PhosphorIconsFill.play,
                      size: 34,
                      color: fg,
                      semanticLabel: failed ? 'Retry' : label, // i18n-ignore
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Up Next, speed, transcript, other devices, save and sleep, in one bar.
class _ActionBar extends StatelessWidget {
  final Episode episode;
  final Color accent;

  const _ActionBar({required this.episode, required this.accent});

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final style = CastawayStyle.of(context);
    final l = L.of(context)!;
    final activeColour = readableOn(accent, style.surface, ratio: 3.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: style.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BarButton(
            key: const Key('nowplaying-upnext'),
            tooltip: l.up_next_queue_label,
            onTap: () => _showPlayerSheet(
              context,
              _tocChapters(episode).isNotEmpty ? _PlayerSheetTab.chapters : _PlayerSheetTab.upNext,
            ),
            child: Icon(PhosphorIconsRegular.queue, size: 24, color: style.text),
          ),
          StreamBuilder<double>(
            stream: audioBloc.currentSpeed,
            initialData: audioBloc.currentSpeed?.valueOrNull ?? 1.0,
            builder: (context, snapshot) {
              final speed = snapshot.data ?? 1.0;
              final text = speed == speed.roundToDouble() ? '${speed.toInt()}×' : '${speed.toStringAsFixed(1)}×';
              return _BarButton(
                tooltip: '${l.playback_speed_label} $text',
                onTap: () => _showSheet(context, const SpeedSlider()),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: speed != 1.0 ? activeColour : style.text,
                  ),
                ),
              );
            },
          ),
          if (episode.hasTranscripts)
            _BarButton(
              tooltip: l.transcript_label,
              onTap: () => _showTranscriptSheet(context, episode),
              child: Icon(PhosphorIconsRegular.article, size: 24, color: style.text),
            ),
          RemoteDevicesButton(color: style.text),
          _SaveButton(activeColour: activeColour),
          StreamBuilder<Sleep>(
            stream: audioBloc.sleepStream,
            initialData: Sleep(type: SleepType.none),
            builder: (context, snapshot) {
              final active = (snapshot.data?.type ?? SleepType.none) != SleepType.none;
              return _BarButton(
                tooltip: l.sleep_timer_label,
                onTap: () => _showSheet(context, const SleepSlider(), scrollControlled: true),
                child: Icon(
                  active ? PhosphorIconsFill.moon : PhosphorIconsRegular.moon,
                  size: 24,
                  color: active ? activeColour : style.text,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  const _BarButton({super.key, required this.tooltip, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkResponse(
          radius: 26,
          onTap: onTap,
          child: SizedBox(width: 52, height: 52, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Star that saves or unsaves the playing episode. Reads the saved state from
/// the server when the episode changes; offline, the change is queued.
class _SaveButton extends StatefulWidget {
  final Color activeColour;

  const _SaveButton({required this.activeColour});

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  int? _episodeId;
  bool? _saved;
  bool _busy = false;

  CastawayService? _service() {
    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
    if (settings.castawayServer == null || settings.castawayApiKey == null) return null;
    return CastawayService()..setCredentials(settings.castawayServer!, settings.castawayApiKey!);
  }

  Future<void> _refresh(int episodeId) async {
    final audio = GlobalServices.castawayAudioService;
    final userId = Provider.of<SettingsBloc>(context, listen: false).currentSettings.castawayUserId;
    final service = _service();
    if (audio == null || userId == null || service == null) return;
    try {
      final meta = await service.getEpisodeMetadata(episodeId, userId, isYoutube: audio.isYoutube);
      if (mounted && _episodeId == episodeId) setState(() => _saved = meta?.saved);
    } catch (_) {
      // Offline or the lookup failed: leave the star as unknown (outlined).
    }
  }

  Future<void> _toggle() async {
    final audio = GlobalServices.castawayAudioService;
    final episodeId = audio?.currentEpisodeId;
    final userId = Provider.of<SettingsBloc>(context, listen: false).currentSettings.castawayUserId;
    final service = _service();
    if (audio == null || episodeId == null || userId == null || service == null || _busy) return;

    final save = _saved != true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = L.of(context)!;
    setState(() {
      _busy = true;
      _saved = save;
    });
    try {
      final ok = save
          ? await service.saveEpisode(episodeId, userId, audio.isYoutube)
          : await service.removeSavedEpisode(episodeId, userId, audio.isYoutube);
      if (!ok) throw Exception('rejected'); // i18n-ignore
      messenger?.showSnackBar(SnackBar(content: Text(save ? l.episode_saved : l.episode_removed_from_saved)));
    } catch (_) {
      final queue = GlobalServices.offlineActionQueue;
      if (queue != null) {
        await queue.enqueueSimple(
          save ? PendingActionType.saveEpisode : PendingActionType.removeSaved,
          episodeId,
          userId,
          audio.isYoutube,
        );
        messenger?.showSnackBar(SnackBar(content: Text(save ? l.saved_sync_when_online : l.removed_sync_when_online)));
      } else if (mounted) {
        setState(() => _saved = !save);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final style = CastawayStyle.of(context);
    final l = L.of(context)!;

    return StreamBuilder<Episode?>(
      stream: audioBloc.nowPlaying,
      initialData: audioBloc.nowPlaying?.valueOrNull,
      builder: (context, snapshot) {
        final id = GlobalServices.castawayAudioService?.currentEpisodeId;
        if (id != null && id != _episodeId) {
          _episodeId = id;
          _saved = null;
          WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(id));
        }
        final saved = _saved == true;
        return _BarButton(
          key: const Key('nowplaying-save'),
          tooltip: saved ? l.remove_from_saved : l.save,
          onTap: _toggle,
          child: Icon(
            saved ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
            size: 24,
            color: saved ? widget.activeColour : style.text,
          ),
        );
      },
    );
  }
}

// Sheets opened from the player.

Future<void> _showSheet(BuildContext context, Widget child, {bool scrollControlled = false}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: scrollControlled,
    backgroundColor: CastawayStyle.of(context).surface,
    builder: (_) => child,
  );
}

/// A sheet the user can drag between a partial and nearly full height, with
/// a handle and title; [builder] gets the sheet's scroll controller.
Future<void> _showDraggableSheet(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, ScrollController controller) builder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: CastawayStyle.of(context).background,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(child: builder(context, controller)),
        ],
      ),
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: CastawayStyle.of(context).surfaceHigh,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

enum _PlayerSheetTab { chapters, upNext, notes }

/// Chapters, Up Next and the episode notes in one sheet with tabs.
void _showPlayerSheet(BuildContext context, _PlayerSheetTab initial) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: CastawayStyle.of(context).background,
    routeSettings: const RouteSettings(name: 'player-lists'),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, controller) => _PlayerSheet(initial: initial, controller: controller),
    ),
  );
}

class _PlayerSheet extends StatefulWidget {
  final _PlayerSheetTab initial;
  final ScrollController controller;

  const _PlayerSheet({required this.initial, required this.controller});

  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  late _PlayerSheetTab _tab = widget.initial;

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final style = CastawayStyle.of(context);
    final l = L.of(context)!;

    return StreamBuilder<Episode?>(
      stream: audioBloc.nowPlaying,
      initialData: audioBloc.nowPlaying?.valueOrNull,
      builder: (context, snapshot) {
        final episode = snapshot.data;
        final hasChapters = episode != null && _tocChapters(episode).isNotEmpty;
        final tabs = [
          if (hasChapters) _PlayerSheetTab.chapters,
          _PlayerSheetTab.upNext,
          _PlayerSheetTab.notes,
        ];
        final tab = tabs.contains(_tab) ? _tab : tabs.first;
        String label(_PlayerSheetTab t) => switch (t) {
              _PlayerSheetTab.chapters => l.chapters_label,
              _PlayerSheetTab.upNext => l.up_next_queue_label,
              _PlayerSheetTab.notes => l.notes_label,
            };

        return Column(
          children: [
            const _SheetHandle(),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: style.surface, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  for (final t in tabs)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: t == tab,
                        label: label(t),
                        excludeSemantics: true,
                        child: GestureDetector(
                          key: ValueKey('player-sheet-${t.name}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _tab = t),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: t == tab ? style.text : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              label(t),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: t == tab ? style.background : style.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (tab) {
                _PlayerSheetTab.chapters => _ChapterList(controller: widget.controller),
                _PlayerSheetTab.upNext => const CastawayUpNextView(),
                _PlayerSheetTab.notes => episode == null
                    ? const SizedBox.shrink()
                    : _NotesView(episode: episode, controller: widget.controller),
              },
            ),
          ],
        );
      },
    );
  }
}

class _NotesView extends StatelessWidget {
  final Episode episode;
  final ScrollController controller;

  const _NotesView({required this.episode, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (episode.persons.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: episode.persons.length,
                itemBuilder: (context, index) => PersonAvatar(person: episode.persons[index]),
              ),
            ),
          PodcastHtml(content: episode.content ?? episode.description ?? ''),
        ],
      ),
    );
  }
}

class _ChapterList extends StatefulWidget {
  final ScrollController controller;

  const _ChapterList({required this.controller});

  @override
  State<_ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends State<_ChapterList> {
  static const _rowHeight = 56.0;
  bool _scrolledToCurrent = false;

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final theme = Theme.of(context);

    return StreamBuilder<Episode?>(
      stream: audioBloc.nowPlaying,
      initialData: audioBloc.nowPlaying?.valueOrNull,
      builder: (context, snapshot) {
        final episode = snapshot.data;
        final chapters = episode == null ? const <Chapter>[] : _tocChapters(episode);
        final current = chapters.indexWhere((c) => c == episode?.currentChapter);

        // Open with the current chapter in view.
        if (!_scrolledToCurrent && current > 1) {
          _scrolledToCurrent = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (widget.controller.hasClients) widget.controller.jumpTo((current - 1) * _rowHeight);
          });
        }

        return ListView.builder(
          controller: widget.controller,
          itemExtent: _rowHeight,
          itemCount: chapters.length,
          itemBuilder: (context, index) {
            final chapter = chapters[index];
            final selected = index == current;
            final color = selected ? CastawayStyle.of(context).link : softNeutral(theme);
            return InkWell(
              onTap: () => audioBloc.transitionPosition(chapter.startTime),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text('${index + 1}', style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)),
                    ),
                    Expanded(
                      child: Text(
                        chapter.title.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: color,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatTime(Duration(milliseconds: (chapter.startTime * 1000).round())),
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.hintColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

void _showTranscriptSheet(BuildContext context, Episode episode) {
  _showDraggableSheet(
    context,
    title: L.of(context)!.transcript_label,
    builder: (context, controller) => _TranscriptList(controller: controller, episode: episode),
  );
}

/// The feed's own (Podcast 2.0) transcript, following playback. Tap a line to
/// play from it.
class _TranscriptList extends StatefulWidget {
  final ScrollController controller;
  final Episode episode;

  const _TranscriptList({required this.controller, required this.episode});

  @override
  State<_TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends State<_TranscriptList> {
  /// Rough row height, used to jump near a line before it has been built.
  static const _estimatedRowHeight = 56.0;

  List<TranscriptCue>? _cues;
  bool _failed = false;
  int _current = -1;
  bool _follow = true;
  final _currentKey = GlobalKey();
  StreamSubscription<PositionState>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _loadFeedTranscript();

    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    _positionSubscription = audioBloc.playPosition?.listen((p) => _onPosition(p.position));
    final now = audioBloc.playPosition?.valueOrNull?.position;
    if (now != null) _onPosition(now, jump: true);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadFeedTranscript() async {
    final urls = widget.episode.transcriptUrls;
    if (urls.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    // Timed formats first; HTML has no timings.
    final url = urls.firstWhere((u) => u.type != TranscriptFormat.html, orElse: () => urls.first);
    try {
      final transcript =
          await Provider.of<PodcastService>(context, listen: false).loadTranscriptByUrl(transcriptUrl: url);
      final cues = [
        for (final s in transcript.subtitles)
          if ((s.data ?? '').trim().isNotEmpty)
            TranscriptCue(
              start: s.start.inMilliseconds / 1000,
              end: (s.end ?? s.start).inMilliseconds / 1000,
              text: _plainText(s.data!),
            ),
      ];
      if (!mounted) return;
      setState(() {
        _cues = cues;
        _failed = cues.isEmpty;
      });
      final now = Provider.of<AudioBloc>(context, listen: false).playPosition?.valueOrNull?.position;
      if (now != null) _onPosition(now, jump: true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  static String _plainText(String data) => data
      .replaceAll('{{HTMLFULL}}', '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _onPosition(Duration position, {bool jump = false}) {
    final cues = _cues;
    if (cues == null || cues.isEmpty) return;
    final seconds = position.inMilliseconds / 1000;
    final index = cues.lastIndexWhere((c) => c.start <= seconds);
    if (index == _current && !jump) return;
    if (mounted) setState(() => _current = index);
    if (_follow && index >= 0) _scrollToCurrent(jump: jump);
  }

  void _scrollToCurrent({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      final row = _currentKey.currentContext;
      if (row != null) {
        Scrollable.ensureVisible(row, alignment: 0.3, duration: Duration(milliseconds: jump ? 0 : 300));
      } else {
        // Not built yet: jump close to it, then settle on it next frame.
        final max = widget.controller.position.maxScrollExtent;
        widget.controller.jumpTo(((_current - 2) * _estimatedRowHeight).clamp(0.0, max));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final settled = _currentKey.currentContext;
          if (settled != null) Scrollable.ensureVisible(settled, alignment: 0.3);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final cues = _cues;

    if (cues == null && !_failed) return const Center(child: CircularProgressIndicator());
    if (cues == null || cues.isEmpty) {
      return Center(
        child: Text(L.of(context)!.no_transcript_available, style: theme.textTheme.bodyMedium!.copyWith(color: theme.hintColor)),
      );
    }

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            if (n.direction != ScrollDirection.idle && _follow) setState(() => _follow = false);
            return false;
          },
          child: ListView.builder(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 72),
            itemCount: cues.length,
            itemBuilder: (context, index) {
              final cue = cues[index];
              final current = index == _current;
              return InkWell(
                key: current ? _currentKey : null,
                borderRadius: BorderRadius.circular(10),
                onTap: () => audioBloc.transitionPosition(cue.start),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          _formatTime(Duration(milliseconds: (cue.start * 1000).round())),
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: theme.hintColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          cue.text,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            height: 1.35,
                            color: current ? CastawayStyle.of(context).link : softNeutral(theme).withOpacity(0.8),
                            fontWeight: current ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (!_follow)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FilterPill(
                label: L.of(context)!.follow_along,
                icon: PhosphorIconsRegular.arrowDown,
                selected: true,
                onTap: () {
                  setState(() => _follow = true);
                  _scrollToCurrent();
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens the Up Next list (the player's sheet, on its Up Next tab), e.g. from
/// the mini player.
void showUpNextSheet(BuildContext context) => _showPlayerSheet(context, _PlayerSheetTab.upNext);
