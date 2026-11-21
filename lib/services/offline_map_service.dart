import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

class LocalMbtilesInfo {
  final String path;
  final String fileName;
  final int sizeBytes;

  const LocalMbtilesInfo({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
  });
}

class CloudMbtilesInfo {
  final String name;
  final int sizeBytes;
  final String downloadUrl;

  const CloudMbtilesInfo({
    required this.name,
    required this.sizeBytes,
    required this.downloadUrl,
  });
}

class OfflineMapService {
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
        'User-Agent': 'FishingRadar/0.3.0 (ru.fishingradar.app)',
      },
    );
  }

  TileProvider createMbtilesTileProvider(String path) {
    return MbTilesTileProvider.fromPath(path: path);
  }

  Future<void> clearCache() async {
    await _cachingProvider.destroy(deleteCache: true);
    _cachingProvider = BuiltInMapCachingProvider.getOrCreateInstance(
      overrideFreshAge: const Duration(days: 30),
    );
  }

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 КБ';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).round()} КБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Future<Directory> _getMbtilesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/offline_maps');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<LocalMbtilesInfo>> listLocalMbtiles() async {
    final dir = await _getMbtilesDir();
    final entities = await dir.list().toList();
    final items = <LocalMbtilesInfo>[];

    for (final entity in entities) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.toLowerCase().endsWith('.mbtiles')) continue;
      final stat = await entity.stat();
      items.add(
        LocalMbtilesInfo(
          path: entity.path,
          fileName: name,
          sizeBytes: stat.size,
        ),
      );
    }

    items.sort((a, b) => a.fileName.compareTo(b.fileName));
    return items;
  }

  Future<LocalMbtilesInfo> importPickedMbtiles(PlatformFile picked) async {
    final rawName = picked.name.trim();
    if (!rawName.toLowerCase().endsWith('.mbtiles')) {
      throw const FormatException('Выберите файл с расширением .mbtiles');
    }

    final dir = await _getMbtilesDir();
    final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final destPath = '${dir.path}/$safeName';
    final destFile = File(destPath);

    if (picked.path != null && picked.path!.isNotEmpty) {
      final src = File(picked.path!);
      await src.copy(destPath);
    } else {
      final bytes = await picked.readAsBytes();
      await destFile.writeAsBytes(bytes, flush: true);
    }

    try {
      _validateMbtilesFile(destPath);
    } catch (e) {
      if (await destFile.exists()) await destFile.delete();
      rethrow;
    }

    final stat = await destFile.stat();
    return LocalMbtilesInfo(
      path: destPath,
      fileName: safeName,
      sizeBytes: stat.size,
    );
  }

  Future<LocalMbtilesInfo?> downloadMbtilesFromUrl({
    required String url,
    required String fileName,
    required void Function(int receivedBytes, int totalBytes) onProgress,
    required bool Function() isCancelled,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('Некорректная ссылка на файл');
    }

    final cleanName = fileName.trim().isEmpty ? 'region.mbtiles' : fileName.trim();
    final finalName = cleanName.toLowerCase().endsWith('.mbtiles')
        ? cleanName
        : '$cleanName.mbtiles';
    final safeName = finalName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

    final dir = await _getMbtilesDir();
    final destPath = '${dir.path}/$safeName';
    final partFile = File('$destPath.part');
    if (await partFile.exists()) await partFile.delete();

    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Сервер вернул ошибку ${response.statusCode}',
          uri: uri,
        );
      }

      final total = response.contentLength;
      var received = 0;
      var lastReported = 0;
      final writeSink = partFile.openWrite();
      sink = writeSink;

      await for (final chunk in response) {
        if (isCancelled()) {
          await writeSink.close();
          sink = null;
          if (await partFile.exists()) await partFile.delete();
          return null;
        }
        writeSink.add(chunk);
        received += chunk.length;
        if (received - lastReported >= 65536 || received == total) {
          lastReported = received;
          onProgress(received, total);
        }
      }

      await writeSink.flush();
      await writeSink.close();
      sink = null;

      onProgress(received, total);
      _validateMbtilesFile(partFile.path);

      final destFile = File(destPath);
      if (await destFile.exists()) await destFile.delete();
      await partFile.rename(destPath);

      final stat = await destFile.stat();
      return LocalMbtilesInfo(
        path: destPath,
        fileName: safeName,
        sizeBytes: stat.size,
      );
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await partFile.exists()) await partFile.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<CloudMbtilesInfo>> listCloudMbtiles() async {
    final api = ApiService();
    if (!api.isBackendConfigured) return [];
    try {
      final objects = await Supabase.instance.client.storage
          .from('offline-maps')
          .list();

      final list = <CloudMbtilesInfo>[];
      for (final obj in objects) {
        if (!obj.name.toLowerCase().endsWith('.mbtiles')) continue;
        final url = Supabase.instance.client.storage
            .from('offline-maps')
            .getPublicUrl(obj.name);
        final size = (obj.metadata?['size'] as num?)?.toInt() ?? 0;
        list.add(
          CloudMbtilesInfo(
            name: obj.name,
            sizeBytes: size,
            downloadUrl: url,
          ),
        );
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteLocalMbtiles(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _validateMbtilesFile(String path) {
    final db = MbTiles(path: path);
    try {
      db.getMetadata();
    } catch (_) {
      throw const FormatException(
        'Файл повреждён или не является корректной базой .mbtiles',
      );
    } finally {
      db.close();
    }
  }
}
