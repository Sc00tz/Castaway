// lib/ui/castaway/people/people_widgets.dart
//
// Shared pieces for people on podcasts and episodes: avatars, the horizontal
// people strip (podcast and episode pages), the follow button, and helpers to
// open a person page or a show.

import 'package:flutter/material.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/people.dart';
import 'package:castaway_mobile/entities/castaway_search.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/castaway/people/person_page.dart';
import 'package:castaway_mobile/ui/castaway/podcast_details.dart';
import 'package:castaway_mobile/ui/castaway/podcast_nav.dart';
import 'package:castaway_mobile/ui/widgets/podcast_image.dart';
import 'package:provider/provider.dart';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';
import 'package:castaway_mobile/l10n/L.dart';

/// A [CastawayService] with the signed-in user's credentials, or null when
/// there is no server connection.
CastawayService? signedInService(BuildContext context) {
  final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
  if (settings.castawayServer == null || settings.castawayApiKey == null) return null;
  return CastawayService()..setCredentials(settings.castawayServer!, settings.castawayApiKey!);
}

Future<void> openPerson(BuildContext context, int personId, {String? name}) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'castaway_person'),
      builder: (context) => PersonPage(personId: personId, initialName: name),
    ),
  );
}

/// Open a show a person is credited on: a library podcast by id, anything else
/// by its feed (like a search result).
void openPersonPodcast(BuildContext context, PersonPodcast show) {
  if (show.inLibrary) {
    navigateToPodcastById(
      context,
      show.podcastId,
      fallbackTitle: show.podcastName,
      fallbackArtwork: show.artworkUrl,
    );
    return;
  }
  if (show.feedUrl.isEmpty) return;
  openFeed(context, title: show.podcastName, feedUrl: show.feedUrl, artwork: show.artworkUrl, indexId: show.podcastIndexId);
}

void openFeed(BuildContext context, {required String title, required String feedUrl, String? artwork, int? indexId}) {
  final podcast = UnifiedCastawayPodcast(
    id: 0,
    indexId: indexId ?? 0,
    title: title,
    url: feedUrl,
    originalUrl: feedUrl,
    link: '',
    description: '',
    author: '',
    ownerName: '',
    image: artwork ?? '',
    artwork: artwork ?? '',
    lastUpdateTime: 0,
    explicit: false,
    episodeCount: 0,
  );
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'castaway_podcast_details'),
      builder: (context) => CastawayPodcastDetails(podcast: podcast, isFollowing: false),
    ),
  );
}

/// A round avatar that falls back to a person icon when there is no image or
/// it fails to load.
class PersonAvatar extends StatelessWidget {
  final String? url;
  final double size;

  const PersonAvatar({super.key, this.url, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(PhosphorIconsRegular.user, size: size * 0.55, color: scheme.onSurfaceVariant),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url == null || url!.isEmpty)
            ? fallback
            : PodcastImage(
                url: url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: fallback,
                errorPlaceholder: fallback,
              ),
      ),
    );
  }
}

/// A titled, horizontally scrolling row of people (nothing when empty).
class PeopleStrip extends StatelessWidget {
  final String title;
  final List<CreditedPerson> people;

  /// Show each person's episode count instead of their role (guest rows).
  final bool showEpisodeCount;

  const PeopleStrip({
    super.key,
    required this.title,
    required this.people,
    this.showEpisodeCount = false,
  });

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title · ${people.length}',
          style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _PersonTile(
                person: people[index],
                detail: showEpisodeCount && people[index].episodeCount > 1
                    ? L.of(context)!.episodes_count(people[index].episodeCount)
                    : roleLabel(people[index].role),
              ),
            ),
          ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  final CreditedPerson person;
  final String detail;

  const _PersonTile({required this.person, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Semantics(
      button: person.canOpen,
      label: [person.name, detail].where((s) => s.isNotEmpty).join(', '),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: person.canOpen ? () => openPerson(context, person.id, name: person.name) : null,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              PersonAvatar(url: person.img, size: 56),
              const SizedBox(height: 6),
              Text(
                person.name,
                style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (detail.isNotEmpty)
                Text(detail, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Follow / Following toggle for a person. Optimistic: flips immediately and
/// reverts with a message if the server refuses.
class PersonFollowButton extends StatefulWidget {
  final int personId;
  final bool followed;
  final ValueChanged<bool>? onChanged;

  const PersonFollowButton({super.key, required this.personId, required this.followed, this.onChanged});

  @override
  State<PersonFollowButton> createState() => _PersonFollowButtonState();
}

class _PersonFollowButtonState extends State<PersonFollowButton> {
  late bool _followed = widget.followed;
  bool _busy = false;

  @override
  void didUpdateWidget(PersonFollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.followed != widget.followed) _followed = widget.followed;
  }

  Future<void> _toggle() async {
    final service = signedInService(context);
    if (service == null || _busy) return;
    final next = !_followed;
    setState(() {
      _followed = next;
      _busy = true;
    });
    var ok = false;
    try {
      ok = await service.setPersonFollowed(widget.personId, next);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _followed = !next;
    });
    if (ok) {
      widget.onChanged?.call(next);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? L.of(context)!.could_not_follow : L.of(context)!.could_not_unfollow)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _followed
        ? OutlinedButton.icon(
            onPressed: _toggle,
            icon: const Icon(PhosphorIconsRegular.check, size: 18),
            label: Text(L.of(context)!.following),
          )
        : FilledButton.icon(
            onPressed: _toggle,
            icon: const Icon(PhosphorIconsRegular.plus, size: 18),
            label: Text(L.of(context)!.subscribe_label),
          );
  }
}
