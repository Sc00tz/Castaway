// Shared look for the redesigned screens (2026-11 mockup): colours taken from
// the current theme, so the Castaway Light/Dark palettes and every other theme
// get a matching, readable result.

import 'package:flutter/material.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';

/// Castaway navy: the brand's dark background and the ink used on bright fills.
const Color castawayNavy = Color(0xff18273a);

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [color] moved lighter or darker (keeping its hue) until it reads on [bg]
/// at [ratio]; returned unchanged when it already does.
Color readableOn(Color color, Color bg, {double ratio = 4.5}) {
  if (contrastRatio(color, bg) >= ratio) return color;
  final darkBg = bg.computeLuminance() < 0.5;
  var hsl = HSLColor.fromColor(color);
  for (var i = 0; i < 40; i++) {
    final l = (hsl.lightness + (darkBg ? 0.025 : -0.025)).clamp(0.0, 1.0);
    hsl = hsl.withLightness(l);
    final c = hsl.toColor();
    if (contrastRatio(c, bg) >= ratio) return c;
  }
  return darkBg ? Colors.white : Colors.black;
}

/// Navy or white, whichever reads better on [fill].
Color inkOn(Color fill) =>
    contrastRatio(castawayNavy, fill) >= contrastRatio(Colors.white, fill) ? castawayNavy : Colors.white;

class CastawayStyle {
  /// Page background.
  final Color background;

  /// Cards, search boxes, the mini player and the player's action bar.
  final Color surface;

  /// One step above [surface] (selected rows, pressed tabs).
  final Color surfaceHigh;

  /// Hairlines between rows.
  final Color divider;

  /// Body text and icons.
  final Color text;

  /// Secondary text (dates, durations, counts), still 4.5:1 on [background].
  final Color muted;

  /// Fill for the play button, progress and the active filter (brand orange).
  final Color accent;

  /// Icons and text drawn on [accent].
  final Color onAccent;

  /// Links, the selected tab and other coloured text (brand blue, readable).
  final Color link;

  /// [accent] as text (readable on [background]).
  final Color accentText;

  const CastawayStyle({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.divider,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.link,
    required this.accentText,
  });

  static CastawayStyle of(BuildContext context) => fromTheme(Theme.of(context));

  static final Map<ThemeData, CastawayStyle> _cache = {};

  static CastawayStyle fromTheme(ThemeData theme) => _cache.putIfAbsent(theme, () {
        final bg = theme.scaffoldBackgroundColor;
        final text = theme.textTheme.bodyLarge?.color ??
            (theme.brightness == Brightness.dark ? Colors.white : castawayNavy);
        Color blend(double amount) => Color.alphaBlend(text.withOpacity(amount), bg);
        final accent = theme.colorScheme.secondary;
        return CastawayStyle(
          background: bg,
          surface: blend(0.06),
          surfaceHigh: blend(0.11),
          divider: blend(0.10),
          text: text,
          muted: readableOn(blend(0.62), bg),
          accent: accent,
          onAccent: inkOn(accent),
          link: readableOn(theme.colorScheme.primary, bg),
          accentText: readableOn(accent, bg),
        );
      });
}

/// Big bold page title with optional actions on the right, used at the top of
/// each tab (Podcasts, Lists, Discover, Profile).
class TabHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  const TabHeader({super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: style.text, height: 1.2),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Round outlined play button used on episode rows.
class RoundPlayButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool playing;
  final String semanticLabel;
  final double size;

  const RoundPlayButton({
    super.key,
    required this.onPressed,
    required this.semanticLabel,
    this.playing = false,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onPressed,
        radius: size / 2 + 4,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: playing ? style.accent : null,
            border: playing ? null : Border.all(color: style.surfaceHigh, width: 2),
          ),
          child: Icon(
            playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
            size: size * 0.4,
            color: playing ? style.onAccent : style.text,
          ),
        ),
      ),
    );
  }
}

/// Search-style box that opens something when tapped (it isn't a text field).
class SearchBoxButton extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;

  const SearchBoxButton({super.key, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: Material(
        color: style.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: style.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: style.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
