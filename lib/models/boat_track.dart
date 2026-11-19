import 'package:latlong2/latlong.dart';

class BoatTrack {
  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final double maxSpeedKmh;
  final List<LatLng> points;

  const BoatTrack({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.maxSpeedKmh,
    required this.points,
  });

  Duration get duration => endedAt.difference(startedAt);

  double get avgSpeedKmh {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return 0.0;
    return (distanceMeters / seconds) * 3.6;
  }

  factory BoatTrack.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List<dynamic>? ?? []);
    return BoatTrack(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Трек').toString(),
      startedAt: DateTime.tryParse((json['started_at'] ?? '').toString()) ??
          DateTime.now(),
      endedAt: DateTime.tryParse((json['ended_at'] ?? '').toString()) ??
          DateTime.now(),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0.0,
      maxSpeedKmh: (json['max_speed_kmh'] as num?)?.toDouble() ?? 0.0,
      points: rawPoints
          .map(
            (e) => LatLng(
              ((e as Map)['lat'] as num).toDouble(),
              (e['lon'] as num).toDouble(),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'distance_meters': distanceMeters,
      'max_speed_kmh': maxSpeedKmh,
      'points': points
          .map((p) => {'lat': p.latitude, 'lon': p.longitude})
          .toList(),
    };
  }
}
