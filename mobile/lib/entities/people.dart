// People credited on podcasts and episodes, as served by the Castaway server's
// /api/data/people/* endpoints. These are distinct from [Person] (person.dart),
// which is the Podcasting 2.0 tag attached to a playing episode.

import 'package:castaway_mobile/entities/castaway_episode.dart';

const String roleHost = 'host';
const String roleCoHost = 'co-host';
const String roleGuest = 'guest';

String? _nonEmpty(dynamic value) {
  final s = value as String?;
  return (s == null || s.isEmpty) ? null : s;
}

List<String> _strings(dynamic value) =>
    (value as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

/// Display label for a Podcasting 2.0 role ("co-host" -> "Co-host").
String roleLabel(String role) {
  if (role.isEmpty) return '';
  return role[0].toUpperCase() + role.substring(1);
}

/// A person as shown on a podcast or episode page.
class CreditedPerson {
  /// Castaway person id; 0 when the server is too old to provide one (then the
  /// person can't be opened or followed).
  final int id;
  final String name;
  final String? img;
  final String? href;

  /// Most significant role ("host", "co-host", "guest", ...).
  final String role;
  final List<String> roles;
  final String? group;

  /// "podcast", "episodes" or "episode".
  final String scope;
  final int episodeCount;
  final List<String> sources;

  final bool followed;

  const CreditedPerson({
    required this.id,
    required this.name,
    this.img,
    this.href,
    this.role = '',
    this.roles = const [],
    this.group,
    this.scope = 'podcast',
    this.episodeCount = 0,
    this.sources = const [],
    this.followed = false,
  });

  factory CreditedPerson.fromJson(Map<String, dynamic> json) {
    return CreditedPerson(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      img: _nonEmpty(json['img']),
      href: _nonEmpty(json['href']),
      role: json['role'] as String? ?? '',
      roles: _strings(json['roles']),
      group: _nonEmpty(json['group']),
      scope: json['scope'] as String? ?? 'podcast',
      episodeCount: json['episode_count'] as int? ?? 0,
      sources: _strings(json['sources']),
      followed: json['followed'] as bool? ?? false,
    );
  }

  /// Whether the person page can be opened (the server knows this person).
  bool get canOpen => id > 0;
}

/// Everyone credited on a podcast: regulars and episode-only guests.
class PodcastCredits {
  final List<CreditedPerson> people;
  final List<CreditedPerson> guests;

  const PodcastCredits({this.people = const [], this.guests = const []});

  factory PodcastCredits.fromJson(Map<String, dynamic> json) {
    List<CreditedPerson> list(String key) => (json[key] as List<dynamic>? ?? const [])
        .map((e) => CreditedPerson.fromJson(e as Map<String, dynamic>))
        .where((p) => p.name.isNotEmpty)
        .toList();
    return PodcastCredits(people: list('people'), guests: list('guests'));
  }
}

/// A person's identity, as on the person page and the followed list.
class PersonInfo {
  final int id;
  final String name;
  final String? img;
  final String? href;
  final bool followed;

  const PersonInfo({
    required this.id,
    required this.name,
    this.img,
    this.href,
    this.followed = false,
  });

  factory PersonInfo.fromJson(Map<String, dynamic> json) {
    return PersonInfo(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      img: _nonEmpty(json['img']),
      href: _nonEmpty(json['href']),
      followed: json['followed'] as bool? ?? false,
    );
  }

  PersonInfo copyWith({bool? followed}) => PersonInfo(
        id: id,
        name: name,
        img: img,
        href: href,
        followed: followed ?? this.followed,
      );
}

/// A podcast a person is credited on.
class PersonPodcast {
  /// The user's podcast id, or null for a show outside their library.
  final int? podcastId;
  final String podcastName;
  final String? artworkUrl;
  final String feedUrl;
  final int? podcastIndexId;
  final List<String> roles;
  final bool podcastLevel;
  final int episodeCount;

  const PersonPodcast({
    this.podcastId,
    required this.podcastName,
    this.artworkUrl,
    required this.feedUrl,
    this.podcastIndexId,
    this.roles = const [],
    this.podcastLevel = false,
    this.episodeCount = 0,
  });

  bool get inLibrary => podcastId != null && podcastId! > 0;

  factory PersonPodcast.fromJson(Map<String, dynamic> json) {
    return PersonPodcast(
      podcastId: json['podcastid'] as int?,
      podcastName: json['podcastname'] as String? ?? '',
      artworkUrl: _nonEmpty(json['artworkurl']),
      feedUrl: json['feedurl'] as String? ?? '',
      podcastIndexId: json['podcastindexid'] as int?,
      roles: _strings(json['roles']),
      podcastLevel: json['podcast_level'] as bool? ?? false,
      episodeCount: json['episode_count'] as int? ?? 0,
    );
  }
}

/// A person's page: who they are, their shows, and their episodes.
class PersonProfile {
  final PersonInfo person;
  final List<PersonPodcast> podcasts;

  /// Library episodes the person is credited on, newest first.
  final List<CastawayEpisode> episodes;

  /// Recent episodes from shows outside the library (episode id 0: played by URL).
  final List<CastawayEpisode> externalEpisodes;

  /// True while the server refreshes [externalEpisodes] in the background.
  final bool refreshing;

  const PersonProfile({
    required this.person,
    this.podcasts = const [],
    this.episodes = const [],
    this.externalEpisodes = const [],
    this.refreshing = false,
  });

  factory PersonProfile.fromJson(Map<String, dynamic> json) {
    List<CastawayEpisode> episodes(String key) => (json[key] as List<dynamic>? ?? const [])
        .map((e) => CastawayEpisode.fromJson(e as Map<String, dynamic>))
        .toList();
    return PersonProfile(
      person: PersonInfo.fromJson(json['person'] as Map<String, dynamic>),
      podcasts: (json['podcasts'] as List<dynamic>? ?? const [])
          .map((e) => PersonPodcast.fromJson(e as Map<String, dynamic>))
          .toList(),
      episodes: episodes('episodes'),
      externalEpisodes: episodes('external_episodes'),
      refreshing: json['refreshing'] as bool? ?? false,
    );
  }
}

/// A people search result.
class PersonHit {
  final int? personId;
  final String name;
  final String? img;
  final bool followed;

  const PersonHit({
    this.personId,
    required this.name,
    this.img,
    this.followed = false,
  });

  factory PersonHit.fromJson(Map<String, dynamic> json) {
    return PersonHit(
      personId: json['person_id'] as int?,
      name: json['name'] as String? ?? '',
      img: _nonEmpty(json['img']),
      followed: json['followed'] as bool? ?? false,
    );
  }
}
