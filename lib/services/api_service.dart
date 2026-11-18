class FishingSpot {
  final String id;
  final double latitude;
  final double longitude;
  final double depthMeters;
  final String bottomType;
  final String fishSpecies;
  final double? fishWeightKg;
  final String comment;
  final bool isPrivateCircle; // Скрывать точную точку в «круге доверия»
  final DateTime createdAt;

  const FishingSpot({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.depthMeters,
    required this.bottomType,
    required this.fishSpecies,
    this.fishWeightKg,
    this.comment = '',
    this.isPrivateCircle = false,
    required this.createdAt,
  });

  factory FishingSpot.fromJson(Map<String, dynamic> json) {
    return FishingSpot(
      id: (json['id'] ?? '').toString(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      depthMeters: (json['depth_meters'] as num?)?.toDouble() ?? 0.0,
      bottomType: (json['bottom_type'] ?? 'Не указано').toString(),
      fishSpecies: (json['fish_species'] ?? 'Не указана').toString(),
      fishWeightKg: (json['fish_weight_kg'] as num?)?.toDouble(),
      comment: (json['comment'] ?? '').toString(),
      isPrivateCircle: json['is_private_circle'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'depth_meters': depthMeters,
      'bottom_type': bottomType,
      'fish_species': fishSpecies,
      'fish_weight_kg': fishWeightKg,
      'comment': comment,
      'is_private_circle': isPrivateCircle,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
