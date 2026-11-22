import 'dart:convert';
import 'dart:io';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

enum WaterwayMarkKind {
  buoy,
  beacon,
  lock,
  dam,
  slipway,
  other,
}

class WaterwayMark {
  final LatLng point;
  final WaterwayMarkKind kind;
  final String title;
  final String detail;

  const WaterwayMark({
    required this.point,
    required this.kind,
    required this.title,
    this.detail = '',
  });
}

class WaterwayOverlayData {
  final List<List<LatLng>> fairwayLines;
  final List<WaterwayMark> marks;
  final bool fromCache;

  const WaterwayOverlayData({
    required this.fairwayLines,
    required this.marks,
    this.fromCache = false,
  });

  static const WaterwayOverlayData empty = WaterwayOverlayData(
    fairwayLines: [],
    marks: [],
  );
}

class WaterwayService {
  static const List<String> _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  final Map<String, WaterwayOverlayData> _memoryCache = {};

  Future<WaterwayOverlayData> fetchForBounds(LatLngBounds bounds) async {
    final s = bounds.south;
    final w = bounds.west;
    final n = bounds.north;
    final e = bounds.east;

    final centerLat = (s + n) / 2.0;
    final centerLon = (w + e) / 2.0;
    final halfLat = ((n - s) / 2.0).clamp(0.01, 0.25);
    final halfLon = ((e - w) / 2.0).clamp(0.01, 0.35);

    final qSouth = centerLat - halfLat;
    final qNorth = centerLat + halfLat;
    final qWest = centerLon - halfLon;
    final qEast = centerLon + halfLon;

    final cacheKey =
        '${qSouth.toStringAsFixed(2)}_${qWest.toStringAsFixed(2)}_'
        '${qNorth.toStringAsFixed(2)}_${qEast.toStringAsFixed(2)}';

    final cached = _memoryCache[cacheKey];
    if (cached != null) {
      return WaterwayOverlayData(
        fairwayLines: cached.fairwayLines,
        marks: cached.marks,
        fromCache: true,
      );
    }

    final bbox =
        '${qSouth.toStringAsFixed(4)},${qWest.toStringAsFixed(4)},'
        '${qNorth.toStringAsFixed(4)},${qEast.toStringAsFixed(4)}';

    final query = '[out:json][timeout:15];'
        '('
        'way["waterway"="fairway"]($bbox);'
        'node["seamark:type"]($bbox);'
        'node["waterway"~"^(lock_gate|dam|weir)\$"]($bbox);'
        'node["leisure"="slipway"]($bbox);'
        ');'
        'out geom;';

    Object? lastErr;
    for (final endpoint in _endpoints) {
      final client = HttpClient();
      try {
        final uri = Uri.parse(endpoint);
        final req = await client.postUrl(uri).timeout(
              const Duration(seconds: 15),
            );
        req.headers.set('User-Agent', 'FishingRadar/0.3.0 (ru.fishingradar.app)');
        req.headers.set('Accept', 'application/json');
        req.headers.set(
          'Content-Type',
          'application/x-www-form-urlencoded; charset=UTF-8',
        );
        final bodyBytes = utf8.encode('data=${Uri.encodeQueryComponent(query)}');
        req.add(bodyBytes);

        final res = await req.close().timeout(const Duration(seconds: 15));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}', uri: uri);
        }

        final raw = await res.transform(utf8.decoder).join();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = _parseResponse(decoded);

        if (_memoryCache.length > 24) {
          _memoryCache.remove(_memoryCache.keys.first);
        }
        _memoryCache[cacheKey] = parsed;
        return parsed;
      } catch (err) {
        lastErr = err;
      } finally {
        client.close(force: true);
      }
    }

    if (lastErr != null) {
      throw lastErr;
    }
    return WaterwayOverlayData.empty;
  }

  WaterwayOverlayData _parseResponse(Map<String, dynamic> json) {
    final elements = (json['elements'] as List<dynamic>?) ?? const [];
    final fairways = <List<LatLng>>[];
    final marks = <WaterwayMark>[];

    for (final item in elements) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final type = map['type']?.toString();

      if (type == 'way') {
        final geom = map['geometry'] as List<dynamic>?;
        if (geom == null || geom.length < 2) continue;
        final pts = <LatLng>[];
        for (final p in geom) {
          if (p is! Map) continue;
          final lat = (p['lat'] as num?)?.toDouble();
          final lon = (p['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            pts.add(LatLng(lat, lon));
          }
        }
        if (pts.length >= 2) {
          fairways.add(pts);
        }
      } else if (type == 'node') {
        final lat = (map['lat'] as num?)?.toDouble();
        final lon = (map['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final tags = map['tags'] is Map
            ? Map<String, dynamic>.from(map['tags'] as Map)
            : <String, dynamic>{};

        marks.add(
          _buildMark(LatLng(lat, lon), tags),
        );
      }
    }

    return WaterwayOverlayData(
      fairwayLines: fairways,
      marks: marks,
    );
  }

  WaterwayMark _buildMark(LatLng point, Map<String, dynamic> tags) {
    final seamarkType = (tags['seamark:type'] ?? '').toString();
    final waterway = (tags['waterway'] ?? '').toString();
    final leisure = (tags['leisure'] ?? '').toString();
    final name =
        (tags['seamark:name'] ?? tags['name'] ?? '').toString().trim();

    if (leisure == 'slipway') {
      return WaterwayMark(
        point: point,
        kind: WaterwayMarkKind.slipway,
        title: name.isNotEmpty ? 'Слип: $name' : 'Слип (спуск лодки)',
        detail: 'Место спуска/подъёма лодки',
      );
    }

    if (waterway == 'lock_gate') {
      return WaterwayMark(
        point: point,
        kind: WaterwayMarkKind.lock,
        title: name.isNotEmpty ? 'Шлюз: $name' : 'Шлюзовые ворота',
        detail: 'Судоходный шлюз',
      );
    }

    if (waterway == 'dam' || waterway == 'weir') {
      return WaterwayMark(
        point: point,
        kind: WaterwayMarkKind.dam,
        title: name.isNotEmpty ? 'Плотина: $name' : 'Плотина / перелив',
        detail: 'Препятствие на реке',
      );
    }

    if (seamarkType.contains('buoy')) {
      final colour = (tags['seamark:buoy_lateral:colour'] ??
              tags['seamark:colour'] ??
              '')
          .toString();
      final detail = colour.isNotEmpty ? 'Цвет: $colour' : 'Навигационный буй';
      return WaterwayMark(
        point: point,
        kind: WaterwayMarkKind.buoy,
        title: name.isNotEmpty ? 'Буй $name' : 'Буй',
        detail: detail,
      );
    }

    if (seamarkType.contains('beacon') ||
        seamarkType.contains('light') ||
        seamarkType.contains('notice')) {
      return WaterwayMark(
        point: point,
        kind: WaterwayMarkKind.beacon,
        title: name.isNotEmpty ? name : 'Навигационный знак',
        detail: seamarkType,
      );
    }

    return WaterwayMark(
      point: point,
      kind: WaterwayMarkKind.other,
      title: name.isNotEmpty ? name : 'Водный знак',
      detail: seamarkType.isNotEmpty ? seamarkType : 'Навигационный объект',
    );
  }
}
