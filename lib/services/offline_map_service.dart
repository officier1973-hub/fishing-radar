import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

class TileDownloadResult {
  final int processed;
  final int total;
  final int saved;
  final int failed;

  const TileDownloadResult({
    required this.processed,
    required this.total,
    required this.saved,
    required this.failed,
  });
}

class OfflineMapService {
  static const int maxTilesPerDownload = 250;
  static const String standardUrlTemplate =
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
      silenceExceptions: true,
      headers: <String, String>{
        'User-Agent': 'FishingRadar/0.2.0 (ru.fishingradar.app)',
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

  int estimateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
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

  Future<TileDownloadResult> downloadRegion({
    required String urlTemplate,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required void Function(int done, int total, int saved) onProgress,
    required bool Function() isCancelled,
  }) async {
    final tiles = buildTilesForBounds(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    if (tiles.isEmpty) {
      return const TileDownloadResult(
        processed: 0,
        total: 0,
        saved: 0,
        failed: 0,
      );
    }

    onProgress(0, tiles.length, 0);

    final provider = createTileProvider();
    final layerConfig = TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'ru.fishingradar.app',
      tileProvider: provider,
    );

    var done = 0;
    var saved = 0;
    var failed = 0;
    const batchSize = 3;

    try {
      for (var i = 0; i < tiles.length; i += batchSize) {
        if (isCancelled()) break;
        final end = math.min(i + batchSize, tiles.length);
        final batch = tiles.sublist(i, end);

        final results = await Future.wait(
          batch.map((coords) => _cacheSingleTile(provider, layerConfig, coords)),
        );

        for (final ok in results) {
          done++;
          if (ok) {
            saved++;
          } else {
            failed++;
          }
        }
        onProgress(done, tiles.length, saved);

        if (end < tiles.length && !isCancelled()) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      }
    } finally {
      await provider.dispose();
    }

    return TileDownloadResult(
      processed: done,
      total: tiles.length,
      saved: saved,
      failed: failed,
    );
  }

  Future<bool> _cacheSingleTile(
    NetworkTileProvider provider,
    TileLayer layerConfig,
    TileCoordinates coords,
  ) async {
    try {
      final url = provider.getTileUrl(coords, layerConfig);
      if (_cachingProvider.isSupported) {
        final existing = await _cachingProvider.getTile(url);
        if (existing != null) {
          return true;
        }
      }

      final imageProvider = provider.getImage(coords, layerConfig);
      final completer = Completer<bool>();
      final stream = imageProvider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;

      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          info.dispose();
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete(true);
        },
        onError: (_, __) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      stream.addListener(listener);
      return await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          stream.removeListener(listener);
          return false;
        },
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCache() async {
    await _cachingProvider.destroy(deleteCache: true);
    _cachingProvider = BuiltInMapCachingProvider.getOrCreateInstance(
      overrideFreshAge: const Duration(days: 30),
    );
  }

  int _lonToTileX(double lon, int zoom) {
    final n = 1 << zoom;
    final x = ((lon + 180.0) / 360.0 * n).floor();
    return x.clamp(0, n - 1);
  }

  int _latToTileY(double lat, int zoom) {
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final latRad = clamped * math.pi / 180.0;
    final n = 1 << zoom;
    final y = ((1.0 -
                math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
            2.0 *
            n)
        .floor();
    return y.clamp(0, n - 1);
  }
}
