import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import '../models/boat_track.dart';
import '../models/fishing_spot.dart';

class GpxParseResult {
  final List<BoatTrack> tracks;
  final List<FishingSpot> spots;

  const GpxParseResult({
    this.tracks = const [],
    this.spots = const [],
  });

  bool get isEmpty => tracks.isEmpty && spots.isEmpty;
}

class GpxService {
  final Distance _distanceCalc = const Distance();

  static String sanitizeFileName(
    String raw, {
    String fallback = 'fishradar_export',
  }) {
    var clean = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s_]+'), '_');
    clean = clean.replaceAll(RegExp(r'^_+|_+$'), '');
    if (clean.isEmpty || clean.toLowerCase() == '.gpx') {
      clean = fallback;
    }
    if (!clean.toLowerCase().endsWith('.gpx')) {
      clean = '$clean.gpx';
    }
    return clean;
  }

  /// Формирует валидный GPX 1.1 XML для треков лодки и точек клёва.
  /// При передаче [currentUserId] чужие приватные точки экспортируются
  /// со смещёнными координатами (без раскрытия секретного места автора).
  String buildGpx({
    List<BoatTrack> tracks = const [],
    List<FishingSpot> spots = const [],
    String? currentUserId,
    String documentName = 'FishRadar Export',
  }) {
    final buf = StringBuffer();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<gpx version="1.1" creator="FishRadar" '
      'xmlns="http://www.topografix.com/GPX/1/1" '
      'xmlns:fishradar="https://fishingradar.ru/gpx/1">',
    );
    buf.writeln('  <metadata>');
    buf.writeln('    <name>${_escapeXml(documentName)}</name>');
    buf.writeln('    <time>$nowIso</time>');
    buf.writeln('  </metadata>');

    for (final spot in spots) {
      final pt = spot.displayPointFor(currentUserId);
      final title = '${spot.fishSpecies} • ${spot.depthMeters.toStringAsFixed(1)} м';
      final descParts = <String>[
        'Глубина: ${spot.depthMeters.toStringAsFixed(1)} м',
        if (spot.bottomType.trim().isNotEmpty) 'Дно: ${spot.bottomType.trim()}',
        'Рыба: ${spot.fishSpecies}',
        if (spot.fishWeightKg != null) 'Вес: ${spot.fishWeightKg} кг',
        if (spot.comment.trim().isNotEmpty) spot.comment.trim(),
      ];

      buf.writeln(
        '  <wpt lat="${pt.latitude.toStringAsFixed(6)}" '
        'lon="${pt.longitude.toStringAsFixed(6)}">',
      );
      buf.writeln('    <time>${spot.createdAt.toUtc().toIso8601String()}</time>');
      buf.writeln('    <name>${_escapeXml(title)}</name>');
      buf.writeln('    <desc>${_escapeXml(descParts.join(' | '))}</desc>');
      buf.writeln('    <type>${_escapeXml(spot.fishSpecies)}</type>');
      buf.writeln('    <extensions>');
      buf.writeln(
        '      <fishradar:depth_m>${spot.depthMeters.toStringAsFixed(2)}</fishradar:depth_m>',
      );
      buf.writeln(
        '      <fishradar:bottom_type>${_escapeXml(spot.bottomType)}</fishradar:bottom_type>',
      );
      buf.writeln(
        '      <fishradar:fish_species>${_escapeXml(spot.fishSpecies)}</fishradar:fish_species>',
      );
      if (spot.fishWeightKg != null) {
        buf.writeln(
          '      <fishradar:fish_weight_kg>${spot.fishWeightKg}</fishradar:fish_weight_kg>',
        );
      }
      if (spot.comment.trim().isNotEmpty) {
        buf.writeln(
          '      <fishradar:comment>${_escapeXml(spot.comment.trim())}</fishradar:comment>',
        );
      }
      buf.writeln('    </extensions>');
      buf.writeln('  </wpt>');
    }

    for (final track in tracks) {
      if (track.points.isEmpty) continue;
      buf.writeln('  <trk>');
      buf.writeln('    <name>${_escapeXml(track.name)}</name>');
      buf.writeln(
        '    <desc>${_escapeXml('Дистанция: ${track.distanceMeters.round()} м | Макс. скорость: ${track.maxSpeedKmh.toStringAsFixed(1)} км/ч')}</desc>',
      );
      buf.writeln('    <trkseg>');

      final totalDurationMs = track.endedAt
          .difference(track.startedAt)
          .inMilliseconds
          .clamp(0, 1000000000);
      final count = track.points.length;

      for (var i = 0; i < count; i++) {
        final p = track.points[i];
        DateTime ptTime;
        if (count <= 1 || totalDurationMs == 0) {
          ptTime = track.startedAt;
        } else {
          final offsetMs = ((totalDurationMs * i) / (count - 1)).round();
          ptTime = track.startedAt.add(Duration(milliseconds: offsetMs));
        }

        buf.writeln(
          '      <trkpt lat="${p.latitude.toStringAsFixed(6)}" '
          'lon="${p.longitude.toStringAsFixed(6)}">',
        );
        buf.writeln('        <time>${ptTime.toUtc().toIso8601String()}</time>');
        buf.writeln('      </trkpt>');
      }

      buf.writeln('    </trkseg>');
      buf.writeln('  </trk>');
    }

    buf.writeln('</gpx>');
    return buf.toString();
  }

  /// Разбирает содержимое GPX-файла (точки `<wpt>`, треки `<trk>`, маршруты `<rte>`).
  GpxParseResult parseGpx(
    String xmlContent, {
    bool importPrivateByDefault = true,
  }) {
    if (xmlContent.trim().isEmpty) {
      return const GpxParseResult();
    }

    final now = DateTime.now();
    final metadataBlock = _extractFirstTag(xmlContent, 'metadata');
    final metadataTime = metadataBlock != null
        ? _parseDateTime(_extractFirstTag(metadataBlock, 'time'))
        : null;

    final spots = <FishingSpot>[];
    final wptMatches = RegExp(
      r'<wpt\b([^>]*?)(?:/>|>([\s\S]*?)</wpt>)',
      caseSensitive: false,
    ).allMatches(xmlContent);

    var wptIndex = 0;
    for (final m in wptMatches) {
      final attrs = m.group(1) ?? '';
      final body = m.group(2) ?? '';
      final lat = _parseAttrDouble(attrs, 'lat');
      final lon = _parseAttrDouble(attrs, 'lon');
      if (lat == null ||
          lon == null ||
          lat < -90 ||
          lat > 90 ||
          lon < -180 ||
          lon > 180) {
        continue;
      }

      final name = _extractFirstTag(body, 'name') ?? '';
      final desc = _extractFirstTag(body, 'desc') ?? '';
      final cmt = _extractFirstTag(body, 'cmt') ?? '';
      final typeTag = _extractFirstTag(body, 'type') ?? '';
      final createdAt =
          _parseDateTime(_extractFirstTag(body, 'time')) ?? metadataTime ?? now;

      final extDepth = _parseDoubleText(
        _extractFirstTag(body, 'fishradar:depth_m'),
      );
      final extBottom = _extractFirstTag(body, 'fishradar:bottom_type');
      final extSpecies = _extractFirstTag(body, 'fishradar:fish_species');
      final extWeight = _parseDoubleText(
        _extractFirstTag(body, 'fishradar:fish_weight_kg'),
      );
      final extComment = _extractFirstTag(body, 'fishradar:comment');

      final depthMeters = extDepth ??
          _extractDepthFromText('$name\n$desc\n$cmt') ??
          0.0;
      final weightKg = extWeight ?? _extractWeightFromText('$desc\n$cmt');

      var fishSpecies = (extSpecies != null && extSpecies.isNotEmpty)
          ? extSpecies
          : (typeTag.isNotEmpty ? typeTag : '');
      if (fishSpecies.isEmpty && name.isNotEmpty) {
        if (name.contains('•')) {
          fishSpecies = name.split('•').first.trim();
        } else if (name.length <= 40) {
          fishSpecies = name;
        }
      }
      if (fishSpecies.isEmpty) {
        fishSpecies = 'Точка GPX';
      }

      final bottomType = (extBottom != null && extBottom.isNotEmpty)
          ? extBottom
          : 'Импорт GPX';

      var comment = extComment ?? '';
      if (comment.isEmpty) {
        final commentParts = <String>[];
        if (name.isNotEmpty &&
            name != fishSpecies &&
            !name.startsWith('$fishSpecies •') &&
            !desc.contains(name)) {
          commentParts.add(name);
        }
        if (desc.isNotEmpty) {
          commentParts.add(desc);
        } else if (cmt.isNotEmpty) {
          commentParts.add(cmt);
        }
        comment = commentParts.join(' — ');
      }

      spots.add(
        FishingSpot(
          id: 'local-gpx-${now.millisecondsSinceEpoch}-$wptIndex',
          latitude: lat,
          longitude: lon,
          depthMeters: depthMeters,
          bottomType: bottomType,
          fishSpecies: fishSpecies,
          fishWeightKg: weightKg,
          comment: comment,
          isPrivateCircle: importPrivateByDefault,
          isSynced: false,
          createdAt: createdAt,
        ),
      );
      wptIndex++;
    }

    final tracks = <BoatTrack>[];
    final trkMatches = RegExp(
      r'<trk\b[^>]*>([\s\S]*?)</trk>',
      caseSensitive: false,
    ).allMatches(xmlContent);

    var trkIndex = 0;
    for (final m in trkMatches) {
      final body = m.group(1) ?? '';
      final headerOnly = body.replaceAll(
        RegExp(r'<trkseg\b[^>]*>[\s\S]*?</trkseg>', caseSensitive: false),
        '',
      );
      final name = _extractFirstTag(headerOnly, 'name');
      final track = _buildTrackFromPointTag(
        body: body,
        pointTag: 'trkpt',
        fallbackName: (name != null && name.isNotEmpty)
            ? name
            : 'Импорт GPX ${trkIndex + 1}',
        fallbackTime: metadataTime ?? now,
        idSeed: '${now.millisecondsSinceEpoch}-trk-$trkIndex',
      );
      if (track != null) {
        tracks.add(track);
        trkIndex++;
      }
    }

    final rteMatches = RegExp(
      r'<rte\b[^>]*>([\s\S]*?)</rte>',
      caseSensitive: false,
    ).allMatches(xmlContent);

    var rteIndex = 0;
    for (final m in rteMatches) {
      final body = m.group(1) ?? '';
      final headerOnly = body.replaceAll(
        RegExp(
          r'<rtept\b[^>]*?(?:/>|>[\s\S]*?</rtept>)',
          caseSensitive: false,
        ),
        '',
      );
      final name = _extractFirstTag(headerOnly, 'name');
      final track = _buildTrackFromPointTag(
        body: body,
        pointTag: 'rtept',
        fallbackName: (name != null && name.isNotEmpty)
            ? name
            : 'Маршрут GPX ${rteIndex + 1}',
        fallbackTime: metadataTime ?? now,
        idSeed: '${now.millisecondsSinceEpoch}-rte-$rteIndex',
      );
      if (track != null) {
        tracks.add(track);
        rteIndex++;
      }
    }

    return GpxParseResult(tracks: tracks, spots: spots);
  }

  /// Открывает системный диалог сохранения GPX-файла.
  /// Возвращает `true`, если файл сохранён, и `false`, если пользователь отменил выбор.
  Future<bool> saveGpxFile({
    required String fileName,
    required String gpxContent,
    String dialogTitle = 'Сохранить GPX-файл',
  }) async {
    final safeName = sanitizeFileName(fileName);
    final bytes = Uint8List.fromList(utf8.encode(gpxContent));
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: safeName,
      bytes: bytes,
    );
    return uri != null;
  }

  /// Открывает проводник для выбора `.gpx` файла и разбирает его содержимое.
  /// Возвращает `null`, если пользователь отменил выбор.
  Future<(String fileName, GpxParseResult result)?> pickAndParseGpxFile() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final ext = (picked.extension ?? '').toLowerCase();
    final lowerName = picked.name.toLowerCase();
    final looksLikeGpx = ext == 'gpx' ||
        lowerName.endsWith('.gpx') ||
        content.toLowerCase().contains('<gpx');

    if (!looksLikeGpx) {
      throw con
