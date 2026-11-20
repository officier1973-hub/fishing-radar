import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../models/fishing_spot.dart';

class ApiService {
  static const String _rawSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseKey = String.fromEnvironment('SUPABASE_KEY');
  static const String _cacheKey = 'cached_fishing_spots_v2';
  static const String _localChatKey = 'cached_region_chat_v1';

  static String get supabaseUrl => _normalizeSupabaseUrl(_rawSupabaseUrl);

  static final ValueNotifier<bool> backendReadyNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<int> pendingCountNotifier =
      ValueNotifier<int>(0);
  static final ValueNotifier<String?> lastErrorNotifier =
      ValueNotifier<String?>(null);

  static bool _initialized = false;

  static String _normalizeSupabaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.scheme.isEmpty || parsed.host.isEmpty) {
      return trimmed.replaceAll(RegExp(r'/+$'), '');
    }
    final portPart = parsed.hasPort ? ':${parsed.port}' : '';
    return '${parsed.scheme}://${parsed.host}$portPart';
  }

  bool get isBackendConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty && _initialized;

  User? get currentUser =>
      isBackendConfigured ? Supabase.instance.client.auth.currentUser : null;

  String? get currentUserId => currentUser?.id;

  String get currentAuthorName {
    final user = currentUser;
    if (user == null) return 'Рыбак';
    final metaName = user.userMetadata?['display_name']?.toString();
    if (metaName != null && metaName.trim().isNotEmpty) return metaName.trim();
    if (user.email != null && user.email!.contains('@')) {
      return user.email!.split('@').first;
    }
    return user.isAnonymous ? 'Гость' : 'Рыбак';
  }

  static Future<void> initSupabase() async {
    final cleanUrl = supabaseUrl;
    if (cleanUrl.isEmpty || supabaseKey.isEmpty || _initialized) return;
    try {
      await Supabase.initialize(
        url: cleanUrl,
        publishableKey: supabaseKey,
      ).timeout(const Duration(seconds: 5));
      _initialized = true;
      backendReadyNotifier.value = true;
    } catch (e) {
      _initialized = false;
      backendReadyNotifier.value = false;
      lastErrorNotifier.value = 'Ошибка подключения: ${_shortError(e)}';
    }
  }

  static String _shortError(Object e) {
    if (e is PostgrestException) return e.message;
    if (e is StorageException) return e.message;
    if (e is AuthException) return e.message;
    final text = e.toString();
    return text.length > 90 ? '${text.substring(0, 90)}...' : text;
  }

  Future<String?> signInWithEmail(String email, String password) async {
    if (!isBackendConfigured) return 'Сервер не подключён';
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Не удалось войти: $e';
    }
  }

  Future<String?> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (!isBackendConfigured) return 'Сервер не подключён';
    try {
      await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Не удалось зарегистрироваться: $e';
    }
  }

  Future<String?> signInAsGuest() async {
    if (!isBackendConfigured) return 'Сервер не подключён';
    try {
      await Supabase.instance.client.auth.signInAnonymously();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Гостевой вход недоступен: $e';
    }
  }

  Future<void> signOut() async {
    if (!isBackendConfigured) return;
    await Supabase.instance.client.auth.signOut();
  }

  Future<String?> uploadPhotoBytes(Uint8List bytes, String ext) async {
    if (!isBackendConfigured) return null;
    final rawExt = ext.trim().toLowerCase();
    final fileExt = rawExt.isEmpty ? 'jpg' : rawExt;
    final mimeSubtype = fileExt == 'jpg' ? 'jpeg' : fileExt;
    final owner = currentUserId ?? 'anon';
    final path = '$owner/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    await Supabase.instance.client.storage.from('spot-photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: 'image/$mimeSubtype',
            upsert: true,
          ),
        );
    return Supabase.instance.client.storage
        .from('spot-photos')
        .getPublicUrl(path);
  }

  Future<List<FishingSpot>> getSpots({
    required double lat,
    required double lon,
    double radiusKm = 50,
  }) async {
    await syncPendingSpots();

    final cached = await _loadFromCache();
    final pendingLocal = cached.where((s) => !s.isSynced).toList();

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
        final remoteSpots = list
            .map(
              (e) => FishingSpot.fromJson(Map<String, dynamic>.from(e as Map))
                  .copyWith(isSynced: true),
            )
            .toList();

        if (pendingLocal.isEmpty) {
          lastErrorNotifier.value = null;
        }
        final merged = [...pendingLocal, ...remoteSpots];
        await _saveToCache(merged);
        _updatePendingCounter(merged);
        return merged;
      } catch (e) {
        lastErrorNotifier.value = 'Ошибка загрузки точек: ${_shortError(e)}';
      }
    }

    _updatePendingCounter(cached);
    final realCached =
        cached.where((s) => !s.id.startsWith('demo-')).toList();
    if (realCached.isNotEmpty) {
      return cached;
    }

    final demo = _demoSpots(lat, lon);
    await _saveToCache(demo);
    return demo;
  }

  Future<FishingSpot> createSpot(
    FishingSpot spot, {
    Uint8List? photoBytes,
    String photoExt = 'jpg',
  }) async {
    var prepared = spot;

    if (prepared.isPrivateCircle &&
        (prepared.publicLatitude == null || prepared.publicLongitude == null)) {
      final shifted = _offsetCoordinate(
        prepared.latitude,
        prepared.longitude,
        minMeters: 120,
        maxMeters: 210,
      );
      prepared = prepared.copyWith(
        publicLatitude: shifted.$1,
        publicLongitude: shifted.$2,
      );
    }

    if (prepared.userId == null && currentUserId != null) {
      prepared = prepared.copyWith(
        userId: currentUserId,
        authorName: currentAuthorName,
      );
    }

    if (isBackendConfigured) {
      try {
        String? uploadedUrl = prepared.photoUrl;
        if (photoBytes != null) {
          uploadedUrl = await uploadPhotoBytes(photoBytes, photoExt);
        } else if (prepared.localPhotoPath != null) {
          final file = File(prepared.localPhotoPath!);
          if (file.existsSync()) {
            uploadedUrl = await uploadPhotoBytes(
              await file.readAsBytes(),
              photoExt,
            );
          }
        }

        final inserted = await _insertIntoSupabase(
          prepared.copyWith(photoUrl: uploadedUrl),
        );
        lastErrorNotifier.value = null;

        final current = await _loadFromCache();
        current.removeWhere((s) => s.id.startsWith('demo-'));
        current.insert(0, inserted);
        await _saveToCache(current);
        _updatePendingCounter(current);
        return inserted;
      } catch (e) {
        lastErrorNotifier.value = 'Не отправлено: ${_shortError(e)}';
      }
    }

    final offlineSpot = prepared.copyWith(
      id: prepared.id.startsWith('local-')
          ? prepared.id
          : 'local-${DateTime.now().millisecondsSinceEpoch}',
      isSynced: false,
    );

    final current = await _loadFromCache();
    current.removeWhere((s) => s.id.startsWith('demo-'));
    current.insert(0, offlineSpot);
    await _saveToCache(current);
    _updatePendingCounter(current);
    return offlineSpot;
  }

  Future<FishingSpot> updateSpot(
    FishingSpot spot, {
    Uint8List? newPhotoBytes,
    String photoExt = 'jpg',
  }) async {
    var updated = spot;
    if (updated.isPrivateCircle &&
        (updated.publicLatitude == null || updated.publicLongitude == null)) {
      final shifted = _offsetCoordinate(
        updated.latitude,
        updated.longitude,
        minMeters: 120,
        maxMeters: 210,
      );
      updated = updated.copyWith(
        publicLatitude: shifted.$1,
        publicLongitude: shifted.$2,
      );
    }

    if (isBackendConfigured && updated.isSynced && !updated.id.startsWith('local-')) {
      try {
        if (newPhotoBytes != null) {
          final url = await uploadPhotoBytes(newPhotoBytes, photoExt);
          updated = updated.copyWith(photoUrl: url);
        }

        final row = await Supabase.instance.client
            .from('fishing_spots')
            .update({
              'depth_meters': updated.depthMeters,
              'bottom_type': updated.bottomType,
              'fish_species': updated.fishSpecies,
              'fish_weight_kg': updated.fishWeightKg,
              'comment': updated.comment,
              'is_private_circle': updated.isPrivateCircle,
              'public_latitude': updated.publicLatitude,
              'public_longitude': updated.publicLongitude,
              'photo_url': updated.photoUrl,
            })
            .eq('id', updated.id)
            .select()
            .single();

        updated = FishingSpot.fromJson(Map<String, dynamic>.from(row))
            .copyWith(isSynced: true);
        lastErrorNotifier.value = null;
      } catch (e) {
        lastErrorNotifier.value = 'Ошибка обновления: ${_shortError(e)}';
      }
    }

    final current = await _loadFromCache();
    final idx = current.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      current[idx] = updated;
    } else {
      current.insert(0, updated);
    }
    await _saveToCache(current);
    return updated;
  }

  Future<void> deleteSpot(FishingSpot spot) async {
    if (isBackendConfigured &&
        spot.isSynced &&
        !spot.id.startsWith('local-') &&
        !spot.id.startsWith('demo-')) {
      try {
        await Supabase.instance.client
            .from('fishing_spots')
            .delete()
            .eq('id', spot.id);
      } catch (e) {
        lastErrorNotifier.value = 'Ошибка удаления: ${_shortError(e)}';
      }
    }

    final current = await _loadFromCache();
    current.removeWhere((s) => s.id == spot.id);
    await _saveToCache(current);
    _updatePendingCounter(current);
  }

  Future<int> syncPendingSpots() async {
    if (!isBackendConfigured) return 0;

    final current = await _loadFromCache();
    final pending = current.where((s) => !s.isSynced).toList();
    if (pending.isEmpty) {
      _updatePendingCounter(current);
      return 0;
    }

    var syncedCount = 0;
    for (final spot in pending) {
      try {
        var prepared = spot;
        if (prepared.localPhotoPath != null && prepared.photoUrl == null) {
          final file = File(prepared.localPhotoPath!);
          if (file.existsSync()) {
            final url = await uploadPhotoBytes(await file.readAsBytes(), 'jpg');
            prepared = prepared.copyWith(photoUrl: url);
          }
        }
        final uploaded = await _insertIntoSupabase(prepared);
        final idx = current.indexWhere((s) => s.id == spot.id);
        if (idx != -1) {
          current[idx] = uploaded;
        }
        syncedCount++;
        lastErrorNotifier.value = null;
      } catch (e) {
        lastErrorNotifier.value = 'Синхронизация: ${_shortError(e)}';
      }
    }

    await _saveToCache(current);
    _updatePendingCounter(current);
    return syncedCount;
  }

  Future<FishingSpot> _insertIntoSupabase(FishingSpot spot) async {
    final payload = <String, dynamic>{
      'latitude': spot.latitude,
      'longitude': spot.longitude,
      'public_latitude': spot.publicLatitude,
      'public_longitude': spot.publicLongitude,
      'depth_meters': spot.depthMeters,
      'bottom_type': spot.bottomType,
      'fish_species': spot.fishSpecies,
      'fish_weight_kg': spot.fishWeightKg,
      'comment': spot.comment,
      'is_private_circle': spot.isPrivateCircle,
      'photo_url': spot.photoUrl,
      'user_id': spot.userId ?? currentUserId,
      'author_name': spot.authorName ?? currentAuthorName,
    };

    final inserted = await Supabase.instance.client
        .from('fishing_spots')
        .insert(payload)
        .select()
        .single();

    return FishingSpot.fromJson(Map<String, dynamic>.from(inserted))
        .copyWith(isSynced: true);
  }

  Future<List<ChatMessage>> fetchRegionMessages(String region) async {
    if (!isBackendConfigured) {
      return _loadLocalChat(region);
    }
    try {
      final rows = await Supabase.instance.client
          .from('region_messages')
          .select()
          .eq('region', region)
          .order('created_at', ascending: true)
          .limit(100)
          .timeout(const Duration(seconds: 8));
      final list = rows as List<dynamic>;
      return list
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return _loadLocalChat(region);
    }
  }

  RealtimeChannel? subscribeToRegionChat(
    String region,
    void Function(ChatMessage message) onMessage,
  ) {
    if (!isBackendConfigured) return null;
    final channelName =
        'region_chat_${region.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    return Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'region_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'region',
            value: region,
          ),
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            onMessage(
              ChatMessage.fromJson(
                Map<String, dynamic>.from(payload.newRecord),
              ),
            );
          },
        )
        .subscribe();
  }

  Future<void> unsubscribeChannel(RealtimeChannel? channel) async {
    if (channel == null || !isBackendConfigured) return;
    try {
      await Supabase.instance.client.removeChannel(channel);
    } catch (_) {}
  }

  Future<(ChatMessage?, String?)> sendRegionMessage(
    String region,
    String text,
  ) async {
    final clean = text.trim();
    if (clean.isEmpty) return (null, null);

    if (!isBackendConfigured) {
      final list = await _loadLocalChat(region);
      final msg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        region: region,
        userId: currentUserId,
        authorName: currentAuthorName,
        text: clean,
        createdAt: DateTime.now(),
      );
      list.add(msg);
      await _saveLocalChat(region, list);
      return (msg, null);
    }

    try {
      final row = await Supabase.instance.client
          .from('region_messages')
          .insert({
            'region': region,
            'user_id': currentUserId,
            'author_name': currentAuthorName,
            'message_text': clean,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 8));
      final msg = ChatMessage.fromJson(Map<String, dynamic>.from(row));
      return (msg, null);
    } catch (e) {
      return (null, _shortError(e));
    }
  }

  Future<List<ChatMessage>> _loadLocalChat(String region) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_localChatKey}_$region');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _saveLocalChat(String region, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${_localChatKey}_$region',
      jsonEncode(
        messages
            .map(
              (m) => {
                'id': m.id,
                'region': m.region,
                'user_id': m.userId,
                'author_name': m.authorName,
                'message_text': m.text,
                'created_at': m.createdAt.toIso8601String(),
              },
            )
            .toList(),
      ),
    );
  }

  (double, double) _offsetCoordinate(
    double lat,
    double lon, {
    required double minMeters,
    required double maxMeters,
  }) {
    final rng = math.Random();
    final dist = minMeters + rng.nextDouble() * (maxMeters - minMeters);
    final angle = rng.nextDouble() * 2 * math.pi;
    final dLat = (dist * math.cos(angle)) / 111320.0;
    final cosLat = math.cos(lat * math.pi / 180.0).abs().clamp(0.1, 1.0);
    final dLon = (dist * math.sin(angle)) / (111320.0 * cosLat);
    return (lat + dLat, lon + dLon);
  }

  void _updatePendingCounter(List<FishingSpot> spots) {
    pendingCountNotifier.value = spots.where((s) => !s.isSynced).length;
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
        .map((e) => FishingSpot.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<FishingSpot> _demoSpots(double lat, double lon) {
    final now = DateTime.now();
    return [
      FishingSpot(
        id: 'demo-1',
        latitude: lat + 0.0022,
        longitude: lon + 0.0032,
        depthMeters: 2.2,
        bottomType: 'Песок / камень',
        fishSpecies: 'Окунь',
        fishWeightKg: 0.6,
        comment: 'Демо-точка на мели: трава и песчаная коса.',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      FishingSpot(
        id: 'demo-2',
        latitude: lat - 0.0020,
        longitude: lon + 0.0038,
        depthMeters: 5.6,
        bottomType: 'Бровка / свал',
        fishSpecies: 'Судак',
        fishWeightKg: 2.3,
        comment: 'Демо-точка на бровке: джиг 18 г, поролон.',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      FishingSpot(
        id: 'demo-3',
        latitude: lat + 0.0034,
        longitude: lon - 0.0028,
        depthMeters: 9.8,
        bottomType: 'Яма',
        fishSpecies: 'Щука',
        fishWeightKg: 4.1,
        comment: 'Демо-точка на яме: выход на зорьке.',
        createdAt: now.subtract(const Duration(hours: 9)),
      ),
    ];
  }
}
