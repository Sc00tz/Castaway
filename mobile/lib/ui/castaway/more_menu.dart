// lib/ui/castaway/more_menu.dart
import 'package:flutter/material.dart';
import 'package:castaway_mobile/ui/library/downloads.dart';
import 'package:castaway_mobile/ui/settings/settings.dart';
import 'package:castaway_mobile/ui/castaway/saved.dart';
import 'package:castaway_mobile/ui/castaway/history.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/l10n/L.dart';

class CastawayMoreMenu extends StatelessWidget {
  // Constructor with optional key parameter
  const CastawayMoreMenu({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L.of(context)!.more_options,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildMenuItem(
                context,
                L.of(context)!.downloads,
                PhosphorIconsRegular.downloadSimple,
                    () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    fullscreenDialog: false,
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: Text(L.of(context)!.downloads)),
                      body: const CustomScrollView(
                        slivers: [Downloads()],
                      ),
                    ),
                  ),
                ),
              ),
              _buildMenuItem(
                context,
                L.of(context)!.saved_and_collections,
                PhosphorIconsRegular.bookmarkSimple,
                    () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    fullscreenDialog: false,
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: Text(L.of(context)!.saved_and_collections)),
                      body: const CustomScrollView(
                        slivers: [CastawaySaved()],
                      ),
                    ),
                  ),
                ),
              ),
              _buildMenuItem(
                context,
                L.of(context)!.history,
                PhosphorIconsRegular.clockCounterClockwise,
                    () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    fullscreenDialog: false,
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: Text(L.of(context)!.history)),
                      body: const CustomScrollView(
                        slivers: [CastawayHistory()],
                      ),
                    ),
                  ),
                ),
              ),
              _buildMenuItem(
                context,
                L.of(context)!.settings_label,
                PhosphorIconsRegular.gear,
                    () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    settings: const RouteSettings(name: 'settings'),
                    builder: (context) => const Settings(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildMenuItem(
      BuildContext context,
      String title,
      IconData icon,
      VoidCallback onTap,
      ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(PhosphorIconsRegular.caretRight, size: 16),
        onTap: onTap,
      ),
    );
  }
}