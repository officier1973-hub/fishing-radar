import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

class OfflineMapService {
  static const int maxTilesPerDownload = 250;
  static const String osmUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String satelliteUrlTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const String seamarkUrlTemplate =
      'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png';

  BuiltInMapCachingProvider _cachingProvider =
      BuiltInMapCachingProvider.getOrCreateInstance(
    overrideFreshAge: const Duration(days: 30),
  );

  NetworkTileProvider createTileProvider() {
    return NetworkTileProvider(
      cachingProvider: _cachingProvider,
      headers: <String, String>{
        'User-Agent': 'FishingRadar/0.1.0 (ru.fishingradar.app)',
      },
    );
  }

  List<TileCoordinates> buildTilesForBounds({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    final result = <TileCoordinates>[];
    final zMin = minZoom.clamp(1, 18);
    final zMax = maxZoom.clamp(zMin, 18);

    for (var z = zMin; z <= zMax; z++) {
      final minX = _lonToTileX(bounds.west, z);
      final maxX = _lonToTileX(bounds.east, z);
      final minY = _latToTileY(bounds.north, z);
      final maxY = _latToTileY(bounds.south, z);

      if (minX > maxX || minY > maxY) continue;

      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          result.add(TileCoordinates(x, y, z));
          if (result.length >= maxTilesPerDownload) {
            return result;
          }
        }
      }
    }
    return result;
  }

  Future<int> estimateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) async {
    var total = 0;
    final zMin = minZoom.clamp(1, 18);
    final zMax = maxZoom.clamp(zMin, 18);
    for (var z = zMin; z <= zMax; z++) {
      final minX = _lonToTileX(bounds.west, z);
      final maxX = _lonToTileX(bounds.east, z);
      final minY = _latToTileY(bounds.north, z);
      final maxY = _latToTileY(bounds.south, z);
      if (minX <= maxX && minY <= maxY) {
        total += (maxX - minX + 1) * (maxY - minY + 1);
      }
    }
    return total;
  }

  Future<int> downloadRegion({
    required String urlTemplate,
    required LatLngBounds bounds,
    requi
