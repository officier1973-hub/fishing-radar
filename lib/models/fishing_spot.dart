import 'package:latlong2/latlong.dart';

class FishingSpot {
  final String id;
  final double latitude;
  final double longitude;
  final double? publicLatitude;
  final double? publicLongitude;
  final double depthMeters;
  final String bottomType;
  final String fishSpecies;
  final double? fishWeightKg;
  final String comment;
  final bool isPrivateCircle;
  final bool isTrustedFriend;
  final String? photoUrl;
  final String? localPhotoPath;
  final String? userId;
  final String? authorName;
  final bool isSynced;
  final DateTime createdAt;

  const FishingSpot({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.publicLatitude,
    this.publicLongitude,
    required this.depthMeters,
    required this.bottomType,
    required this.fishSpecies,
    this.fishWeightKg,
    this.comment = '',
    this.isPrivateCircle = false,
    this.isTrustedFriend = false,
    this.photoUrl,
    this.localPhotoPath,
    this.userId,
    this.authorName,
    this.isSynced = true,
    required this.createdAt,
  });

  bool isOwnedBy(String? currentUserId) {
    if (userId == null || userId!.isEmpty) {
      return id.startsWith('local-') || id.startsWith('demo-');
    }
    return currentUserId != null && userId == currentUserId;
  }

  /// Для владельца и доверенного друга — точная координата, для чужих — смещённая
  LatLng displayPointFor(String? currentUserId) {
    if (isPrivateCircle && !isOwnedBy(currentUserId) && !isTrustedFriend) {
      if (publicLatitude != null && publicLongitude != null) {
        return LatLng(publicLatitude!, publicLongitude!);
      }
    }
    return LatLng(latitude, longitude);
  }

  FishingSpot copyWith({
    String? id,
    double? latitude,
    double? longitude,
    double? publicLatitude,
    double? publicLongitude,
    double? depthMeters,
    String? bottomType,
    String? fishSpecies,
    double? fishWeightKg,
    bool clearWeight = false,
    String? comment,
    bool? isPrivateCircle,
    bool? isTrustedFriend,
    String? photoUrl,
    bool clearPhotoUrl = false,
    String? localPhotoPath,
    bool clearLocalPhotoPath = false,
    String? userId,
    String? authorName,
    bool? isSynced,
    DateTime? createdAt,
  }) {
    return FishingSpot(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      publicLatitude: publicLatitude ?? this.publicLatitude,
      publicLongitude: publicLongitude ?? this.publicLongitude,
      depthMeters: depthMeters ?? this.depthMeters,
      bottomType: bottomType ?? this.bottomType,
      fishSpecies: fishSpecies ?? this.fishSpecies,
      fishWeightKg: clearWeight ? null : (fishWeightKg ?? this.fishWeightKg),
      comment: comment ?? this.comment,
      isPrivateCircle: isPrivateCircle ?? this.isPrivateCircle,
      isTrustedFriend: isTrustedFriend ?? this.isTrustedFriend,
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      localPhotoPath: clearLocalPhotoPath
          ? null
          : (localPhotoPath ?? this.localPhotoPath),
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory FishingSpot.fromJson(Map<String, dynamic> json) {
    return FishingSpot(
      id: (json['id'] ?? '').toString(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      publicLatitude: (json['public_latitude'] as num?)?.toDouble(),
      publicLongitude: (json['public_longitude'] as num?)?.toDouble(),
      depthMeters: (json['depth_meters'] as num?)?.toDouble() ?? 0.0,
      bottomType: (json['bottom_type'] ?? 'Не указано').toString(),
      fishSpecies: (json['fish_species'] ?? 'Не указана').toString(),
      fishWeightKg: (json['fish_weight_kg'] as num?)?.toDouble(),
      comment: (json['comment'] ?? '').toString(),
      isPrivateCircle: json['is_private_circle'] == true,
      isTrustedFriend: json['is_trusted_friend'] == true,
      photoUrl: json['photo_url']?.toString(),
      localPhotoPath: json['local_photo_path']?.toString(),
      userId: json['user_id']?.toString(),
      authorName: json['author_name']?.toString(),
      isSynced: json['is_synced'] != false,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'public_latitude': publicLatitude,
      'public_longitude': publicLongitude,
      'depth_meters': depthMeters,
      'bottom_type': bottomType,
      'fish_species': fishSpecies,
      'fish_weight_kg': fishWeightKg,
      'comment': comment,
      'is_private_circle': isPrivateCircle,
      'is_trusted_friend': isTrustedFriend,
      'photo_url': photoUrl,
      'local_photo_path': localPhotoPath,
      'user_id': userId,
      'author_name': authorName,
      'is_synced': isSynced,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
