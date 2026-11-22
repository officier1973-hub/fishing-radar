import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/boat_track.dart';

enum BaseMapType { standard, satellite, hybrid }

enum RingPreset {
  off('Выкл', []),
  shore('Берег (25/50/100 м)', [25.0, 50.0, 100.0]),
  boat('Лодка (50/100/200 м)', [50.0, 100.0, 200.0]),
  openWater('Большая вода (100/250/500 м)', [100.0, 250.0, 500.0]);

  final String label;
  final List<double> radii;

  const RingPreset(this.label, this.radii);
}

enum DepthFilter {
  all('Все глубины'),
  shallow('Мель (< 3 м)'),
  mid('Бровка (3–7 м)'),
  deep('Ямы (> 7 м)');

  final String label;
  const DepthFilter(this.label);

  bool matches(double depth) {
    return switch (this) {
      DepthFilter.all => true,
      DepthFilter.shallow => depth < 3.0,
      DepthFilter.mid => depth >= 3.0 && depth <= 7.0,
      DepthFilter.deep => depth > 7.0,
    };
  }
}

class MapLayerSettings {
  final BaseMapType baseMap;
  final bool showSeamarks;
  final bool onlyMySpots;
  final String fishFilter;
  final RingPreset ringPreset;
  final DepthFilter depthFilter;
  final String? activeMbtilesPath;
  final String? overlayMbtilesPath;

  const MapLayerSettings({
    this.baseMap = BaseMapType.standard,
    this.showSeamarks = false,
    this.onlyMySpots = false,
    this.fishFilter = '',
    this.ringPreset = RingPreset.boat,
    this.depthFilter = DepthFilter.all,
    this.activeMbtilesPath,
    this.overlayMbtilesPath,
  });

  MapLayerSettings copyWith({
    BaseMapType? baseMap,
    bool? showSeamarks,
    bool? onlyMySpots,
    String? fishFilter,
    RingPreset? ringPreset,
    DepthFilter? depthFilter,
    String? activeMbtilesPath,
    bool clearActiveMbtiles = false,
    String? overlayMbtilesPath,
    bool clearOverlayMbtiles = false,
  }) {
    return MapLayerSettings(
      baseMap: baseMap ?? this.baseMap,
      showSeamarks: showSeamarks ?? this.showSeamarks,
      onlyMySpots: onlyMySpots ?? this.onlyMySpots,
      fishFilter: fishFilter ?? this.fishFilter,
      ringPreset: ringPreset ?? this.ringPreset,
      depthFilter: depthFilter ?? this.depthFilter,
      activeMbtilesPath: clearActiveMbtiles
          ? null
          : (activeMbtilesPath ?? this.activeMbtilesPath),
      overlayMbtilesPath: clearOverlayMbtiles
          ? null
          : (overlayMbtilesPath ?? this.overlayMbtilesPath),
    );
  }
}

class TrackService {
  static const String _tracksKey = 'saved_boat_tracks_v1';
  static const String _settingsKey = 'map_layer_settings_v3';

  Future<List<BoatTrack>> loadTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tracksKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => BoatTrack.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveTrack(BoatTrack track) async {
    final current = await loadTracks();
    current.insert(0, track);
    await _persistTracks(current);
  }

  Future<void> deleteTrack(String id) async {
    final current = await loadTracks();
    current.removeWhere((t) => t.id == id);
    await _persistTracks(current);
  }

  Future<void> _persistTracks(List<BoatTrack> tracks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tracksKey,
      jsonEncode(tracks.map((t) => t.toJson()).toList()),
    );
  }

  Future<MapLayerSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const MapLayerSettings();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final baseIdx = (map['base_map'] as num?)?.toInt() ?? 0;
    final ringIdx = (map['ring_preset'] as num?)?.toInt() ?? 2;
    final depthIdx = (map['depth_filter'] as num?)?.toInt() ?? 0;
    return MapLayerSettings(
      baseMap:
          BaseMapType.values[baseIdx.clamp(0, BaseMapType.values.length - 1)],
      showSeamarks: map['show_seamarks'] == true,
      onlyMySpots: map['only_my_spots'] == true,
      fishFilter: (map['fish_filter'] ?? '').toString(),
      ringPreset:
          RingPreset.values[ringIdx.clamp(0, RingPreset.values.length - 1)],
      depthFilter:
          DepthFilter.values[depthIdx.clamp(0, DepthFilter.values.length - 1)],
      activeMbtilesPath: map['active_mbtiles_path']?.toString(),
      overlayMbtilesPath: map['overlay_mbtiles_path']?.toString(),
    );
  }

  Future<void> saveSettings(MapLayerSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _settingsKey,
      jsonEncode({
        'base_map': settings.baseMap.index,
        'show_seamarks': settings.showSeamarks,
        'only_my_spots': settings.onlyMySpots,
        'fish_filter': settings.fishFilter,
        'ring_preset': settings.ringPreset.index,
        'depth_filter': settings.depthFilter.index,
        'active_mbtiles_path': settings.activeMbtilesPath,
        'overlay_mbtiles_path': settings.overlayMbtilesPath,
      }),
    );
  }
}
