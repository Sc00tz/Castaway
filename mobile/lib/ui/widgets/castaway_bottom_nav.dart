// lib/ui/widgets/castaway_bottom_nav.dart
import 'package:flutter/material.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';
import 'package:castaway_mobile/l10n/L.dart';

/// The app's four tabs, in bar order. Everything else (Feed, Saved, Downloads,
/// History, Playlists, Home) lives under Lists; People and Settings under
/// Profile. Decided 2026-11-19 with the Pocket Casts-style redesign.
enum CastawayTab { podcasts, lists, discover, profile }

String castawayTabLabel(BuildContext context, CastawayTab tab) {
  final l = L.of(context)!;
  return switch (tab) {
    CastawayTab.podcasts => l.podcasts,
    CastawayTab.lists => l.nav_lists,
    CastawayTab.discover => l.nav_discover,
    CastawayTab.profile => l.nav_profile,
  };
}

IconData castawayTabIcon(CastawayTab tab, {bool selected = false}) {
  return switch (tab) {
    CastawayTab.podcasts => selected ? PhosphorIconsFill.squaresFour : PhosphorIconsRegular.squaresFour,
    CastawayTab.lists => selected ? PhosphorIconsFill.listDashes : PhosphorIconsRegular.listDashes,
    CastawayTab.discover => selected ? PhosphorIconsFill.compass : PhosphorIconsRegular.compass,
    CastawayTab.profile => selected ? PhosphorIconsFill.userCircle : PhosphorIconsRegular.userCircle,
  };
}

/// Fixed bottom bar with the four tabs. [selectedIndex] is a [CastawayTab] index.
class CastawayBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const CastawayBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 66 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: style.background,
        border: Border(top: BorderSide(color: style.divider, width: 1)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Row(
            children: [
              for (final tab in CastawayTab.values)
                Expanded(
                  child: _NavSlot(
                    tab: tab,
                    selected: tab.index == selectedIndex,
                    onTap: () => onSelect(tab.index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final CastawayTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _NavSlot({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    final colour = selected ? style.link : style.muted;
    final label = castawayTabLabel(context, tab);

    // Opaque so the whole slot is tappable, not just the icon and text.
    return GestureDetector(
      key: ValueKey('tab-${tab.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(castawayTabIcon(tab, selected: selected), color: colour, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colour,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
