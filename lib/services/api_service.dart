import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fishing_spot.dart';

class ApiService {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseKey = String.fromEnvironment('SUPABASE_KEY');
  static const String _cacheKey = 'cached_fishing_spots_v1';

  static bool _initialized = false;

  bool get isBackendConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty && _initialized;

  static Future<void> initSupabase() async {
    if (supabaseUrl.isEmpty || supabaseKey.isEmpty) return;
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseKey,
      );
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<List<FishingSpot>> getSpots({
    required double lat,
    required double lon,
    double radiusKm = 50,
  }) async {
    if (isBackendConfigured) {
      try {
        final response = await Supabase.instance.client.rpc(
          'get_spots_nearby',
          params: {
            'user_lat': lat,
            'user_lon': lon,
            'radius_meters': radiusKm * 1000.0,
          },
        );

        final List<dynamic> list = response as List<dynamic>;
        final spots = list
            .map((e) => FishingSpot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        await _saveToCache(spots);
        return spots;
      } catch (_) {
        // Нет интернета на реке — берем из локального кеша
      }
    }

    final cached = await _loadFromCache();
    if (cached.isNotEmpty) return cached;

    final demo = _demoSpots(lat, lon);
    await _saveToCache(demo);
    return demo;
  }

  Future<FishingSpot> createSpot(FishingSpot spot) async {
    FishingSpot savedSpot = spot;

    if (isBackendConfigured) {
      try {
        final payload = {
          'latitude': spot.latitude,
          'longitude': spot.longitude,
          'depth_meters': spot.depthMeters,
          'bottom_type': spot.bottomType,
          'fish_species': spot.fishSpecies,
          'fish_weight_kg': spot.fishWeightKg,
          'comment': spot.comment,
          'is_private_circle': spot.isPrivateCircle,
        };

        final inserted = await Supabase.instance.client
            .from('fishing_spots')
            .insert(payload)
            .select(
              'id, latitude, longitude, depth_meters, bottom_type, '
              'fish_species, fish_weight_kg, comment, is_private_circle, created_at',
            )
            .single();

        savedSpot = FishingSpot.fromJson(Map<String, dynamic>.from(inserted));
      } catch (_) {
        // В офлайне сохраняем локально
      }
    }

    final current = await _loadFromCache();
    current.insert(0, savedSpot);
    await _saveToCache(current);
    return savedSpot;
  }

  Future<void> _saveToCache(List<FishingSpot> spots) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(spots.map((s) => s.toJson()).toList());
    await prefs.setString(_cacheKey, encoded);
  }

  Future<List<FishingSpot>> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return [];
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => FishingSpot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<FishingSpot> _demoSpots(double lat, double lon) {
    return [
      FishingSpot(
        id: 'demo-1',
        latitude: lat + 0.004,
        longitude: lon + 0.006,
        depthMeters: 6.5,
        bottomType: 'Ракушечник / бровка',
        fishSpecies: 'Судак',
        fishWeightKg: 2.3,
        comment: 'Выход на зорьке, джиг 18 г, поролон.',
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      ),
    ];
  }
}
