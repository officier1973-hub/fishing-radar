import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WaterwayMarkKind {
  buoy,
  beacon,
  lock,
  dam,
  slipway,
  other,
}

class WaterwayLoadException implements Exception {
  final String summary;
  const WaterwayLoadException(this.summary);

  @override
  String toString() => summary;
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

  Map<String, dynamic> toJson() {
    return {
      'lat': point.latitude,
      'lon': point.longitude,
      'kind': kind.index,
      'title': title,
      'detail': detail,
    };
  }

  factory WaterwayMark.fromJson(Map<String, dynamic> json) {
    final kindIdx = (json['kind'] as num?)?.toInt() ?? 5;
    return WaterwayMark(
      point: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lon'] as num).toDouble(),
      ),
      kind: WaterwayMarkKind
          .values[kindIdx.clamp(0, WaterwayMarkKind.values.length - 1)],
      title: (json['title'] ?? 'Водный знак').toString(),
      detail: (json['detail'] ?? '').toString(),
    );
  }
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

  Map<String, dynamic> toJson() {
    return {
      'lines': fairwayLines
          .map(
            (line) => line.map((p) => [p.latitude, p.longitude]).toList(),
          )
          .toList(),
      'marks': marks.map((m) => m.toJson()).toList(),
    };
  }

  factory WaterwayOverlayData.fromJson(
    Map<String, dynamic> json, {
    bool fromCache = true,
  }) {
    final rawLines = (json['lines'] as List<dynamic>?) ?? const [];
    final lines = <List<LatLng>>[];
    for (final rawLine in rawLines) {
      if (rawLine is! List) continue;
      final pts = <LatLng>[];
      for (final rawPt in rawLine) {
        if (rawPt is List && rawPt.length >= 2) {
          final lat = (rawPt[0] as num?)?.toDouble();
          final lon = (rawPt[1] as num?)?.toDouble();
          if (lat != null && lon != null) {
            pts.add(LatLng(lat, lon));
          }
        }
      }
      if (pts.length >= 2) {
        lines.add(pts);
      }
    }

    final rawMarks = (json['marks'] as List<dynamic>?) ?? const [];
    final marks = rawMarks
        .whereType<Map>()
        .map((m) => WaterwayMark.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return WaterwayOverlayData(
      fairwayLines: lines,
      marks: marks,
      fromCache: fromCache,
    );
  }
}

class WaterwayService {
  static const List<({String tag, String url})> _endpoints = [
    (tag: 'coffee', url: 'https://overpass.private.coffee/api/interpreter'),
    (tag: 'fr', url: 'https://overpass.openstreetmap.fr/api/interpreter'),
    (tag: 'z', url: 'https://z.overpass-api.de/api/interpreter'),
    (tag: 'lz4', url: 'https://lz4.overpass-api.de/api/interpreter'),
    (tag: 'de', url: 'https://overpass-api.de/api/interpreter'),
    (
      tag: 'mail',
      url: 'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    ),
  ];

  static const String _diskCachePrefix = 'waterway_cache_v1_';
  static const String _diskKeysIndexKey = 'waterway_cache_keys_v1';
  static const Duration _diskCacheTtl = Duration(days: 7);
  static const Duration _endpointCooldown = Duration(minutes: 2);

  final Map<String, WaterwayOverlayData> _memoryCache = {};
  final Map<String, DateTime> _cooldownUntil = {};
  String? _lastWorkingTag;

  Future<WaterwayOverlayData> fetchForBounds(LatLngBounds bounds) async {
    final s = bounds.south;
    final w = bounds.west;
    final n = bounds.north;
    final e = bounds.east;

    final centerLat = (s + n) / 2.0;
    final centerLon = (w + e) / 2.0;
    final halfLat = ((n - s) / 2.0).clamp(0.01, 0.16);
    final halfLon = ((e - w) / 2.0).clamp(0.01, 0.22);

    final qSouth = centerLat - halfLat;
    final qNorth = centerLat + halfLat;
    final qWest = centerLon - halfLon;
    final qEast = centerLon + halfLon;

    final cacheKey =
        '${qSouth.toStringAsFixed(2)}_${qWest.toStringAsFixed(2)}_'
        '${qNorth.toStringAsFixed(2)}_${qEast.toStringAsFixed(2)}';

    final memCached = _memoryCache[cacheKey];
    if (memCached != null) {
      return WaterwayOverlayData(
        fairwayLines: memCached.fairwayLines,
        marks: memCached.marks,
        fromCache: true,
      );
    }

    final diskEntry = await _loadFromDiskCache(cacheKey);
    if (diskEntry != null && !diskEntry.isExpired) {
      _putMemoryCache(cacheKey, diskEntry.data);
      return diskEntry.data;
    }

    final bbox =
        '${qSouth.toStringAsFixed(4)},${qWest.toStringAsFixed(4)},'
        '${qNorth.toStringAsFixed(4)},${qEast.toStringAsFixed(4)}';

    final query = '[out:json][timeout:18];'
        '('
        'way["waterway"="fairway"]($bbox);'
        'node["seamark:type"]($bbox);'
        'node["waterway"="lock_gate"]($bbox);'
        'node["waterway"="dam"]($bbox);'
        'node["waterway"="weir"]($bbox);'
        'node["leisure"="slipway"]($bbox);'
        ');'
        'out geom;';

    final now = DateTime.now();
    final ordered = List<({String tag, String url})>.from(_endpoints);
    if (_lastWorkingTag != null) {
      ordered.sort((a, b) {
        if (a.tag == _lastWorkingTag) return -1;
        if (b.tag == _lastWorkingTag) return 1;
        return 0;
      });
    }

    var activeEndpoints = ordered.where((ep) {
      final until = _cooldownUntil[ep.tag];
      return until == null || !now.isBefore(until);
    }).toList();
    if (activeEndpoints.isEmpty) {
      _cooldownUntil.clear();
      activeEndpoints = ordered;
    }

    final errors = <String>[];
    for (final ep in activeEndpoints) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final uri = Uri.parse(ep.url);
        final req = await client.postUrl(uri).timeout(
              const Duration(seconds: 8),
            );
        req.headers.set(
          'User-Agent',
          'FishingRadar/0.3.0 (ru.fishingradar.app)',
        );
        req.headers.set('Accept', 'application/json');
        req.headers.set(
          'Content-Type',
          'application/x-www-form-urlencoded; charset=UTF-8',
        );
        final bodyBytes = utf8.encode(
          'data=${Uri.encodeQueryComponent(query)}',
        );
        req.contentLength = bodyBytes.length;
        req.add(bodyBytes);

        final res = await req.close().timeout(const Duration(seconds: 18));
        final raw = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));

        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}', uri: uri);
        }

        final dynamic decodedAny = jsonDecode(raw);
        if (decodedAny is! Map<String, dynamic>) {
          throw const FormatException('Некорректный формат ответа');
        }
        if (decodedAny['elements'] is! List) {
          final remark = decodedAny['remark']?.toString() ?? '';
          throw FormatException(
            remark.isNotEmpty ? remark : 'Нет списка элементов',
          );
        }

        final parsed = _parseResponse(decodedAny);
        _lastWorkingTag = ep.tag;
        _cooldownUntil.remove(ep.tag);
        _putMemoryCache(cacheKey, parsed);
        await _saveToDiskCache(cacheKey, parsed);
        return parsed;
      } catch (err) {
        _cooldownUntil[ep.tag] = DateTime.now().add(_endpointCooldown);
        errors.add('${ep.tag}:${_shortErrTag(err)}');
      } finally {
        client.close(force: true);
      }
    }

    if (diskEntry != null) {
      _putMemoryCache(cacheKey, diskEntry.data);
      return diskEntry.data;
    }

    throw WaterwayLoadException(errors.take(4).join(', '));
  }

  String _shortErrTag(Object err) {
    if (err is HttpException) {
      return err.message.replaceFirst('HTTP ', '');
    }
    if (err is TimeoutException) return 'таймаут';
    if (err is SocketException) return 'сеть';
    if (err is FormatException) return 'формат';
    return 'сбой';
  }

  void _putMemoryCache(String key, WaterwayOverlayData data) {
    if (_memoryCache.length >= 24) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = data;
  }

  Future<({WaterwayOverlayData data, bool isExpired})?> _loadFromDiskCache(
    String key,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_diskCachePrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedMs = (decoded['saved_at_ms'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - savedMs;
      final data = WaterwayOverlayData.fromJson(
        Map<String, dynamic>.from(decoded['data'] as Map),
        fromCache: true,
      );
      return (data: data, isExpired: age > _diskCacheTtl.inMilliseconds);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToDiskCache(String key, WaterwayOverlayData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = List<String>.from(
        prefs.getStringList(_diskKeysIndexKey) ?? const [],
      );
      keys.remove(key);
      keys.add(key);
      while (keys.length > 16) {
        final oldest = keys.removeAt(0);
        await prefs.remove('$_diskCachePrefix$oldest');
      }
      await prefs.setStringList(_diskKeysIndexKey, keys);
      await prefs.setString(
        '$_diskCachePrefix$key',
        jsonEncode({
          'saved_at_ms': DateTime.now().millisecondsSinceEpoch,
          'data': data.toJson(),
        }),
      );
    } catch (_) {}
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
