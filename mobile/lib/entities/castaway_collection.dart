// lib/entities/castaway_collection.dart

/// A named, hand-picked group of episodes. The default collection is "Saved".
class CastawayCollection {
  final int id;
  final String name;
  final String? description;
  final bool isDefault;

  /// Phosphor class name from the web app, e.g. `ph-bookmark-simple`.
  final String icon;
  final int episodeCount;

  /// Podcast categories whose new episodes are added automatically; null when off.
  final List<String>? autoAddCategories;

  const CastawayCollection({
    required this.id,
    required this.name,
    this.description,
    required this.isDefault,
    required this.icon,
    required this.episodeCount,
    this.autoAddCategories,
  });

  factory CastawayCollection.fromJson(Map<String, dynamic> json) {
    return CastawayCollection(
      id: (json['collection_id'] as num).toInt(),
      name: json['name'] ?? '',
      description: json['description'] as String?,
      isDefault: json['is_default'] == true,
      icon: json['icon'] ?? 'ph-bookmark-simple',
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      autoAddCategories: (json['auto_add_categories'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
