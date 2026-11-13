// lib/ui/widgets/hide_played.dart
//
// The "Hide played" toggle shared by every episode list. Each list remembers
// its own choice between launches.

import 'package:flutter/widgets.dart';
import 'package:pinepods_mobile/l10n/L.dart';
import 'package:pinepods_mobile/ui/icons/phosphor_icons.dart';
import 'package:pinepods_mobile/ui/widgets/soft_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

mixin HidePlayed<T extends StatefulWidget> on State<T> {
  /// Where this list's choice is saved, e.g. 'saved_hide_played'.
  String get hidePlayedKey;

  bool hidePlayed = false;

  /// Hook for lists that filter into their own field: called inside the
  /// setState that changes [hidePlayed], so the list can refilter.
  void onHidePlayedChanged() {}

  /// Read the saved choice (call from initState).
  Future<void> loadHidePlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final hide = prefs.getBool(hidePlayedKey) ?? false;
    if (!mounted || hide == hidePlayed) return;
    setState(() {
      hidePlayed = hide;
      onHidePlayedChanged();
    });
  }

  Future<void> toggleHidePlayed() async {
    setState(() {
      hidePlayed = !hidePlayed;
      onHidePlayedChanged();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hidePlayedKey, hidePlayed);
  }

  /// Turn the toggle off (for "Clear filters"); call inside setState.
  void resetHidePlayed() {
    if (!hidePlayed) return;
    hidePlayed = false;
    SharedPreferences.getInstance().then((p) => p.setBool(hidePlayedKey, false));
  }

  /// [items] without the played ones when the toggle is on.
  List<E> withoutPlayed<E>(List<E> items, bool Function(E) isPlayed) =>
      hidePlayed ? items.where((e) => !isPlayed(e)).toList() : items;

  /// The toolbar pill for this list.
  ToolbarFilter hidePlayedFilter(BuildContext context) => ToolbarFilter(
        label: L.of(context)!.hide_played,
        icon: hidePlayed ? PhosphorIconsFill.eyeSlash : PhosphorIconsRegular.eyeSlash,
        selected: hidePlayed,
        onTap: toggleHidePlayed,
      );
}

/// A drag within a filtered list ([visible] holds the shown items' indices in the full list),
/// as a move in the full list: the item lands just before the one it was dropped on, or just
/// after the last shown one. Indices follow ReorderableList's convention (the new index counts
/// the moved item still in place).
(int, int) visibleMoveToFull(List<int> visible, int oldIndex, int newIndex) {
  final from = visible[oldIndex];
  final to = newIndex < visible.length ? visible[newIndex] : visible.last + 1;
  return (from, to);
}
