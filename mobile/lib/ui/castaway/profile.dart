// The Profile tab (2026-11 redesign): who is signed in, listening stats,
// followed people, adding a podcast by its feed address, and Settings.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:castaway_mobile/api/podcast/mobile_podcast_api.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/core/environment.dart';
import 'package:castaway_mobile/entities/app_settings.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/castaway/people/followed_people.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:castaway_mobile/ui/castaway/user_stats.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/ui/settings/settings.dart';
import 'package:castaway_mobile/ui/widgets/castaway_style.dart';

class CastawayProfile extends StatelessWidget {
  const CastawayProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final settingsBloc = Provider.of<SettingsBloc>(context);

    return MultiSliver(children: [
      SliverToBoxAdapter(child: TabHeader(title: l.nav_profile)),
      SliverToBoxAdapter(
        child: StreamBuilder<AppSettings>(
          stream: settingsBloc.settings,
          initialData: settingsBloc.currentSettings,
          builder: (context, snapshot) => _AccountCard(settings: snapshot.data ?? settingsBloc.currentSettings),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        sliver: SliverList.list(children: [
          _ProfileRow(
            key: const ValueKey('profile-stats'),
            icon: PhosphorIconsRegular.chartBar,
            title: l.user_statistics,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (context) => const CastawayUserStats()),
            ),
          ),
          _ProfileRow(
            key: const ValueKey('profile-people'),
            icon: PhosphorIconsRegular.users,
            title: l.nav_people,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'people'),
                builder: (context) => Scaffold(
                  appBar: AppBar(title: Text(l.nav_people)),
                  body: const CustomScrollView(slivers: [CastawayPeople()]),
                ),
              ),
            ),
          ),
          _ProfileRow(
            key: const ValueKey('profile-addFeed'),
            icon: PhosphorIconsRegular.rss,
            title: l.add_podcast_by_address,
            onTap: () => showAddFeedDialog(context),
          ),
          _ProfileRow(
            key: const ValueKey('profile-settings'),
            icon: PhosphorIconsRegular.gear,
            title: l.settings_label,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                settings: const RouteSettings(name: 'settings'),
                builder: (context) => const Settings(),
              ),
            ),
          ),
          if (feedbackUrl.isNotEmpty)
            _ProfileRow(
              icon: PhosphorIconsRegular.chatCircleText,
              title: l.feedback_menu_item_label,
              onTap: () => launchUrl(Uri.parse(feedbackUrl), mode: LaunchMode.externalApplication),
            ),
        ]),
      ),
    ]);
  }
}

class _AccountCard extends StatelessWidget {
  final AppSettings settings;

  const _AccountCard({required this.settings});

  static String _gravatar(String email) {
    final hash = md5.convert(utf8.encode(email.toLowerCase().trim())).toString();
    return 'https://www.gravatar.com/avatar/$hash?s=128&d=identicon';
  }

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    final username = settings.castawayUsername ?? '';
    final email = settings.castawayUseGravatar ? settings.castawayEmail : null;
    final server = Uri.tryParse(settings.castawayServer ?? '')?.host ?? '';
    const logo = AssetImage('assets/images/castaway-logo.png');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: style.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 56,
                height: 56,
                child: email != null && email.isNotEmpty
                    ? Image.network(
                        _gravatar(email),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => const Image(image: logo, fit: BoxFit.cover),
                      )
                    : const Image(image: logo, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: style.text),
                  ),
                  if (server.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      server,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: style.muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileRow({super.key, required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = CastawayStyle.of(context);
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(icon, size: 24, color: style.text),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: style.text)),
                ),
                Icon(PhosphorIconsRegular.caretRight, size: 18, color: style.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ask for a feed address, load it, and open that podcast's page.
Future<void> showAddFeedDialog(BuildContext context) async {
  final controller = TextEditingController();
  final l = L.of(context)!;
  final url = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.add_rss_feed_option),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: 'https://'), // i18n-ignore
        onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(l.cancel_button_label)),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(l.ok_button_label),
        ),
      ],
    ),
  );
  controller.dispose();
  if (url == null || url.isEmpty || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final podcast = await MobilePodcastApi().loadFeed(url);
    final unifiedPodcast = UnifiedCastawayPodcast(
      id: 0,
      indexId: 0,
      title: podcast.title ?? L.current.unknown_podcast,
      url: url,
      originalUrl: url,
      link: podcast.link ?? url,
      description: podcast.description ?? '',
      author: podcast.copyright ?? '',
      ownerName: podcast.copyright ?? '',
      image: podcast.image ?? '',
      artwork: podcast.image ?? '',
      lastUpdateTime: 0,
      categories: null,
      explicit: false,
      episodeCount: podcast.episodes.length,
    );

    var isFollowing = false;
    if (context.mounted) {
      final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
      final userId = settings.castawayUserId;
      if (userId != null && settings.castawayServer != null && settings.castawayApiKey != null) {
        try {
          final service = CastawayService()..setCredentials(settings.castawayServer!, settings.castawayApiKey!);
          isFollowing = await service.checkPodcastExists(unifiedPodcast.title, url, userId);
        } catch (_) {}
      }
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // the progress dialog
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'castawaypodcastdetails'),
        builder: (context) => CastawayPodcastDetails(
          podcast: unifiedPodcast,
          isFollowing: isFollowing,
          onFollowChanged: (_) {},
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // the progress dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L.of(context)!.failed_to_load_podcast(e.toString())), backgroundColor: Colors.red),
    );
  }
}
