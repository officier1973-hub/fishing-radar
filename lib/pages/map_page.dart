import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/boat_track.dart';
import '../models/fishing_spot.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/offline_map_service.dart';
import '../services/track_service.dart';
import '../widgets/map_sheets.dart';
import 'auth_page.dart';
import 'chat_page.dart';
import 'report_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();
  final TrackService _trackService = TrackService();
  final OfflineMapService _offlineService = OfflineMapService();
  final Distance _distanceCalc = const Distance();

  late TileProvider _tileProvider;

  LatLng _currentCenter = const LatLng(53.2001, 50.1500);
  double _currentZoom = 13.0;
  LatLng? _myPosition;
  double? _myHeadingDeg;
  double _speedKmh = 0.0;
  double _mapRotationDeg = 0.0;
  bool _isMapReady = false;

  List<FishingSpot> _spots = [];
  MapLayerSettings _settings = const MapLayerSettings();

  final List<LatLng> _trackPoints = [];
  StreamSubscription<Position>? _trackSub;
  bool _isTracking = false;
  DateTime? _trackStartTime;
  double _trackDistanceMeters = 0.0;
  double _trackMaxSpeedKmh = 0.0;

  BoatTrack? _loadedTrack;

  LatLng? _navTargetPoint;
  String? _navTargetLabel;

  bool _isRulerMode = false;
  final List<LatLng> _rulerPoints = [];

  bool _isLoading = true;
  int _pendingSyncCount = 0;
  String? _syncStatusNote;

  @override
  void initState() {
    super.initState();
    _tileProvider = _createSafeTileProvider();
    ApiService.backendReadyNotifier.addListener(_onBackendReady);
    ApiService.pendingCountNotifier.addListener(_onStatusChanged);
    ApiService.lastErrorNotifier.addListener(_onStatusChanged);
    _initData();
  }

  TileProvider _createSafeTileProvider() {
    try {
      return _offlineService.createTileProvider();
    } catch (_) {
      return NetworkTileProvider();
    }
  }

  void _onBackendReady() {
    if (ApiService.backendReadyNotifier.value && mounted) {
      _loadSpots();
    }
  }

  void _onStatusChanged() {
    if (!mounted) return;
    setState(() {
      _pendingSyncCount = ApiService.pendingCountNotifier.value;
      _syncStatusNote = ApiService.lastErrorNotifier.value;
    });
  }

  @override
  void dispose() {
    ApiService.backendReadyNotifier.removeListener(_onBackendReady);
    ApiService.pendingCountNotifier.removeListener(_onStatusChanged);
    ApiService.lastErrorNotifier.removeListener(_onStatusChanged);
    _trackSub?.cancel();
    _tileProvider.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _safeMove(LatLng center, double zoom) {
    if (!_isMapReady) return;
    try {
      _mapController.move(center, zoom);
      _currentZoom = zoom;
    } catch (_) {}
  }

  double _zoneRadiusMeters(double baseMeters, double minPixels) {
    final cosLat = math
        .cos(_currentCenter.latitude * math.pi / 180.0)
        .abs()
        .clamp(0.1, 1.0);
    final metersPerPixel =
        156543.03392 * cosLat / math.pow(2.0, _currentZoom);
    return math.max(baseMeters, minPixels * metersPerPixel);
  }

  Future<void> _initData() async {
    try {
      final savedSettings = await _trackService.loadSettings();
      if (mounted) {
        setState(() => _settings = savedSettings);
      }

      final pos = await _locationService.getCurrentPosition();
      if (pos != null && mounted) {
        _myPosition = LatLng(pos.latitude, pos.longitude);
        _currentCenter = _myPosition!;
        if (pos.heading >= 0) {
          _myHeadingDeg = pos.heading;
        }
        _safeMove(_currentCenter, 14);
      }
    } catch (_) {}
    await _loadSpots();
  }

  Future<void> _loadSpots() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final spots = await _apiService.getSpots(
        lat: _currentCenter.latitude,
        lon: _currentCenter.longitude,
      );
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _updateSettings(MapLayerSettings next) {
    setState(() => _settings = next);
    _trackService.saveSettings(next);
  }

  void _showGpsErrorSnack(LocationPermission perm) {
    if (!mounted) return;
    final forever = perm == LocationPermission.deniedForever;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          forever
              ? 'Доступ к геолокации запрещён в настройках телефона'
              : 'Включите GPS и разрешите доступ к геолокации',
        ),
        action: forever
            ? SnackBarAction(
                label: 'Настройки',
                onPressed: _locationService.openAppSettings,
              )
            : SnackBarAction(
                label: 'GPS',
                onPressed: _locationService.openLocationSettings,
              ),
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    final perm = await _locationService.checkAndRequestPermission();
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      _showGpsErrorSnack(perm);
      return;
    }

    final pos = await _locationService.getCurrentPosition();
    if (pos == null) {
      _showGpsErrorSnack(perm);
      return;
    }
    final point = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _myPosition = point;
      _currentCenter = point;
      if (pos.heading >= 0) _myHeadingDeg = pos.heading;
    });
    _safeMove(point, 15);
  }

  Future<void> _toggleTrackRecording() async {
    if (_isTracking) {
      await _trackSub?.cancel();
      _trackSub = null;
      final pointsCopy = List<LatLng>.from(_trackPoints);
      final started = _trackStartTime ?? DateTime.now();
      final ended = DateTime.now();
      final dist = _trackDistanceMeters;
      final maxSpd = _trackMaxSpeedKmh;

      setState(() {
        _isTracking = false;
        _speedKmh = 0.0;
      });

      if (pointsCopy.length >= 2 && mounted) {
        await _promptSaveTrack(
          points: pointsCopy,
          startedAt: started,
          endedAt: ended,
          distanceMeters: dist,
          maxSpeedKmh: maxSpd,
        );
      }
      return;
    }

    final perm = await _locationService.checkAndRequestPermission();
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      _showGpsErrorSnack(perm);
      return;
    }

    setState(() {
      _isTracking = true;
      _trackPoints.clear();
      _trackStartTime = DateTime.now();
      _trackDistanceMeters = 0.0;
      _trackMaxSpeedKmh = 0.0;
      if (_myPosition != null) _trackPoints.add(_myPosition!);
    });

    _trackSub = _locationService.getPositionStream().listen((pos) {
      final point = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;

      final speed = (pos.speed >= 0 ? pos.speed : 0) * 3.6;
      var addedDist = 0.0;
      if (_trackPoints.isNotEmpty) {
        addedDist = _distanceCalc.as(
          LengthUnit.Meter,
          _trackPoints.last,
          point,
        );
      }

      setState(() {
        _myPosition = point;
        _speedKmh = speed;
        if (pos.heading >= 0 && pos.speed > 0.4) {
          _myHeadingDeg = pos.heading;
        }
        if (addedDist >= 2.0 || _trackPoints.isEmpty) {
          _trackDistanceMeters += addedDist;
          _trackPoints.add(point);
        }
        if (speed > _trackMaxSpeedKmh) {
          _trackMaxSpeedKmh = speed;
        }
      });
    });
  }

  Future<void> _promptSaveTrack({
    required List<LatLng> points,
    required DateTime startedAt,
    required DateTime endedAt,
    required double distanceMeters,
    required double maxSpeedKmh,
  }) async {
    final defaultName = 'Выезд ${DateFormat('dd.MM HH:mm').format(startedAt)}';
    final controller = TextEditingController(text: defaultName);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранить трек?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Дистанция: ${formatDistance(distanceMeters)} • '
              'Время: ${formatDuration(endedAt.difference(startedAt))}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Название трека',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Не сохранять'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (shouldSave != true) {
      controller.dispose();
      return;
    }

    final track = BoatTrack(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: controller.text.trim().isEmpty ? defaultName : controller.text.trim(),
      startedAt: startedAt,
      endedAt: endedAt,
      distanceMeters: distanceMeters,
      maxSpeedKmh: maxSpeedKmh,
      points: points,
    );
    controller.dispose();

    await _trackService.saveTrack(track);
    if (!mounted) return;
    setState(() => _loadedTrack = track);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Трек «${track.name}» сохранён')),
    );
  }

  void _setNavTarget(LatLng point, String label) {
    setState(() {
      _navTargetPoint = point;
      _navTargetLabel = label;
    });
  }

  void _clearNavTarget() {
    setState(() {
      _navTargetPoint = null;
      _navTargetLabel = null;
    });
  }

  void _showMapLongPressMenu(LatLng point) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_location_alt),
              title: const Text('Добавить точку клёва здесь'),
              subtitle: Text(
                '${point.latitude.toStringAsFixed(5)}, '
                '${point.longitude.toStringAsFixed(5)}',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _openCreateSpot(point);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation),
              title: const Text('Проложить курс сюда'),
              subtitle: const Text('Показать расстояние, азимут и линию курса'),
              onTap: () {
                Navigator.of(ctx).pop();
                _setNavTarget(point, 'Точка на карте');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateSpot(LatLng point) async {
    final result = await Navigator.of(context).push<ReportResult>(
      MaterialPageRoute(builder: (_) => ReportPage(initialPoint: point)),
    );
    if (result == null) return;

    final saved = await _apiService.createSpot(
      result.spot,
      photoBytes: result.photoBytes,
      photoExt: result.photoExt,
    );
    if (!mounted) return;
    setState(() {
      _spots.removeWhere((s) => s.id.startsWith('demo-'));
      _spots.insert(0, saved);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.isSynced
              ? 'Точка сохранена и отправлена в облако'
              : (ApiService.lastErrorNotifier.value ??
                  'Точка сохранена на телефон'),
        ),
      ),
    );
  }

  Future<void> _openEditSpot(FishingSpot spot) async {
    final result = await Navigator.of(context).push<ReportResult>(
      MaterialPageRoute(
        builder: (_) => ReportPage(
          initialPoint: LatLng(spot.latitude, spot.longitude),
          existingSpot: spot,
        ),
      ),
    );
    if (result == null) return;

    final updated = await _apiService.updateSpot(
      result.spot,
      newPhotoBytes: result.photoBytes,
      photoExt: result.photoExt,
    );
    if (!mounted) return;
    setState(() {
      final idx = _spots.indexWhere((s) => s.id == updated.id);
      if (idx != -1) _spots[idx] = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Точка обновлена')),
    );
  }

  Future<void> _confirmDeleteSpot(FishingSpot spot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить точку?'),
        content: Text('${spot.fishSpecies} • ${spot.depthMeters} м'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _apiService.deleteSpot(spot);
    if (!mounted) return;
    setState(() => _spots.removeWhere((s) => s.id == spot.id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Точка удалена')),
    );
  }

  void _openFullPhoto({String? url, String? localPath}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: localPath != null && File(localPath).existsSync()
                  ? Image.file(File(localPath))
                  : Image.network(url!),
            ),
          ),
        ),
      ),
    );
  }

  void _showSpotDetails(FishingSpot spot) {
    final myId = _apiService.currentUserId;
    final isMine = spot.isOwnedBy(myId);
    final spotPoint = spot.displayPointFor(myId);
    final fromPoint = _myPosition ?? _currentCenter;
    final distMeters = _distanceCalc.as(LengthUnit.Meter, fromPoint, spotPoint);
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(spot.createdAt);

    final hasLocalPhoto =
        spot.localPhotoPath != null && File(spot.localPhotoPath!).existsSync();
    final hasRemotePhoto = spot.photoUrl != null && spot.photoUrl!.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.phishing, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${spot.fishSpecies} • глубина ${spot.depthMeters} м',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (hasLocalPhoto || hasRemotePhoto) ...[
                GestureDetector(
                  onTap: () => _openFullPhoto(
                    url: hasRemotePhoto ? spot.photoUrl : null,
                    localPath: hasLocalPhoto ? spot.localPhotoPath : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 170,
                      width: double.infinity,
                      child: hasLocalPhoto
                          ? Image.file(
                              File(spot.localPhotoPath!),
                              fit: BoxFit.cover,
                            )
                          : Image.network(spot.photoUrl!, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text('Рельеф дна: ${spot.bottomType}'),
              if (spot.fishWeightKg != null)
                Text('Вес улова: ${spot.fishWeightKg} кг'),
              Text('Расстояние: ${formatDistance(distMeters)}'),
              if (spot.authorName != null && spot.authorName!.isNotEmpty)
                Text('Рыбак: ${spot.authorName}'),
              Text('Дата: $dateStr'),
              if (!spot.isSynced)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Chip(
                    avatar: Icon(Icons.cloud_off, size: 18),
                    label: Text('Ждёт отправки в облако'),
                  ),
                ),
              if (spot.isPrivateCircle)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Chip(
                    avatar: const Icon(Icons.shield, size: 18),
                    label: Text(
                      isMine
                          ? 'Круг доверия: вы видите точную точку'
                          : 'Круг доверия: зона 250 м (точная точка скрыта)',
                    ),
                  ),
                ),
              if (spot.comment.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(spot.comment),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.navigation),
                  label: const Text('Курс на эту точку'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _setNavTarget(
                      spotPoint,
                      '${spot.fishSpecies} (${spot.depthMeters} м)',
                    );
                  },
                ),
              ),
              if (isMine) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Изменить'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _openEditSpot(spot);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Удалить'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _confirmDeleteSpot(spot);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _depthColor(double depth) {
    if (depth < 3) return Colors.teal;
    if (depth < 7) return Colors.blue;
    if (depth < 12) return Colors.indigo;
    return Colors.deepPurple;
  }

  String _compassDirection(double bearingDeg) {
    const dirs = ['С', 'СВ', 'В', 'ЮВ', 'Ю', 'ЮЗ', 'З', 'СЗ'];
    final idx = (((bearingDeg % 360) + 360) % 360 / 45).round() % 8;
    return dirs[idx];
  }

  double get _rulerTotalMeters {
    if (_rulerPoints.length < 2) return 0.0;
    var sum = 0.0;
    for (var i = 1; i < _rulerPoints.length; i++) {
      sum += _distanceCalc.as(
        LengthUnit.Meter,
        _rulerPoints[i - 1],
        _rulerPoints[i],
      );
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final myId = _apiService.currentUserId;
    final ringCenter = _myPosition ?? _currentCenter;

    final filteredSpots = _spots.where((s) {
      if (!_settings.depthFilter.matches(s.depthMeters)) return false;
      if (_settings.onlyMySpots && !s.isOwnedBy(myId)) return false;
      if (_settings.fishFilter.isNotEmpty) {
        final q = _settings.fishFilter.toLowerCase();
        if (!s.fishSpecies.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();

    final baseUrl = _settings.baseMap == BaseMapType.satellite
        ? OfflineMapService.satelliteUrlTemplate
        : OfflineMapService.standardUrlTemplate;

    final navOrigin = _myPosition ?? _currentCenter;
    double? navDistanceMeters;
    double? navBearingDeg;
    if (_navTargetPoint != null) {
      navDistanceMeters = _distanceCalc.as(
        LengthUnit.Meter,
        navOrigin,
        _navTargetPoint!,
      );
      final rawBearing = _distanceCalc.bearing(navOrigin, _navTargetPoint!);
      navBearingDeg = ((rawBearing % 360) + 360) % 360;
    }

    final outerDepthRadius = _zoneRadiusMeters(250, 48);
    final innerDepthRadius = _zoneRadiusMeters(120, 28);
    final heatOuterRadius = _zoneRadiusMeters(320, 68);
    final heatMidRadius = _zoneRadiusMeters(180, 44);
    final heatCoreRadius = _zoneRadiusMeters(90, 24);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FishRadar'),
        actions: [
          IconButton(
            tooltip: 'Чат водоёмов',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ChatPage()),
              );
            },
          ),
          IconButton(
            tooltip: 'Сохранённые треки',
            icon: Icon(
              Icons.timeline,
              color: _loadedTrack != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => showSavedTracksSheet(
              context: context,
              trackService: _trackService,
              activeLoadedTrack: _loadedTrack,
              onSelectTrack: (track) {
                setState(() => _loadedTrack = track);
                if (track != null && track.points.length >= 2 && _isMapReady) {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(track.points),
                      padding: const EdgeInsets.all(48),
                    ),
                  );
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Офлайн-карты (скачать район)',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: () {
              if (!_isMapReady) return;
              showOfflineCacheSheet(
                context: context,
                offlineService: _offlineService,
                visibleBounds: _mapController.camera.visibleBounds,
                baseMap: _settings.baseMap,
                onCacheCleared: () {
                  final old = _tileProvider;
                  setState(() => _tileProvider = _createSafeTileProvider());
                  old.dispose();
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Слои, глубины и фильтры',
            icon: const Icon(Icons.layers),
            onPressed: () => showLayersSheet(
              context: context,
              current: _settings,
              onChanged: _updateSettings,
            ),
          ),
          IconButton(
            tooltip: 'Профиль и синхронизация',
            icon: Badge(
              isLabelVisible: _pendingSyncCount > 0,
              label: Text('$_pendingSyncCount'),
              child: Icon(
                _apiService.currentUser != null
                    ? Icons.account_circle
                    : Icons.account_circle_outlined,
              ),
            ),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const AuthPage()),
              );
              if (changed == true && mounted) {
                await _loadSpots();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: _currentZoom,
              onMapReady: () {
                _isMapReady = true;
                if (_myPosition != null) {
                  _safeMove(_myPosition!, 14);
                }
              },
              onTap: (_, point) {
                if (_isRulerMode) {
                  setState(() => _rulerPoints.add(point));
                }
              },
              onLongPress: (_, point) {
                if (!_isRulerMode) {
                  _showMapLongPressMenu(point);
                }
              },
              onPositionChanged: (camera, _) {
                _currentCenter = camera.center;
                final rotDiff = (camera.rotation - _mapRotationDeg).abs();
                final zoomDiff = (camera.zoom - _currentZoom).abs();
                if (rotDiff > 1.0 || zoomDiff > 0.15) {
                  setState(() {
                    _mapRotationDeg = camera.rotation;
                    _currentZoom = camera.zoom;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: baseUrl,
                userAgentPackageName: 'ru.fishingradar.app',
                tileProvider: _tileProvider,
                maxNativeZoom: 19,
              ),
              if (_settings.showSeamarks)
                TileLayer(
                  urlTemplate: OfflineMapService.seamarkUrlTemplate,
                  userAgentPackageName: 'ru.fishingradar.app',
                  tileProvider: _tileProvider,
                  maxNativeZoom: 18,
                ),
              if (_settings.showDepthZones && filteredSpots.isNotEmpty)
                CircleLayer(
                  circles: [
                    ...filteredSpots.map((s) {
                      final pt = s.displayPointFor(myId);
                      final color = _depthColor(s.depthMeters);
                      return CircleMarker(
                        point: pt,
                        radius: outerDepthRadius,
                        useRadiusInMeter: true,
                        color: color.withValues(alpha: 0.22),
                        borderColor: color.withValues(alpha: 0.60),
                        borderStrokeWidth: 1.8,
                      );
                    }),
                    ...filteredSpots.map((s) {
                      final pt = s.displayPointFor(myId);
                      final color = _depthColor(s.depthMeters);
                      return CircleMarker(
                        point: pt,
                        radius: innerDepthRadius,
                        useRadiusInMeter: true,
                        color: color.withValues(alpha: 0.36),
                        borderStrokeWidth: 0,
                      );
                    }),
                  ],
                ),
              if (_settings.showHeatmap && filteredSpots.isNotEmpty)
                CircleLayer(
                  circles: [
                    ...filteredSpots.map(
                      (s) => CircleMarker(
                        point: s.displayPointFor(myId),
                        radius: heatOuterRadius,
                        useRadiusInMeter: true,
                        color: Colors.amber.withValues(alpha: 0.22),
                        borderStrokeWidth: 0,
                      ),
                    ),
                    ...filteredSpots.map(
                      (s) => CircleMarker(
                        point: s.displayPointFor(myId),
                        radius: heatMidRadius,
                        useRadiusInMeter: true,
                        color: Colors.deepOrange.withValues(alpha: 0.34),
                        borderStrokeWidth: 0,
                      ),
                    ),
                    ...filteredSpots.map(
                      (s) => CircleMarker(
                        point: s.displayPointFor(myId),
                        radius: heatCoreRadius,
                        useRadiusInMeter: true,
                        color: Colors.redAccent.withValues(alpha: 0.48),
                        borderStrokeWidth: 0,
                      ),
                    ),
                  ],
                ),
              if (_settings.ringPreset.radii.isNotEmpty)
                CircleLayer(
                  circles: _settings.ringPreset.radii
                      .map(
                        (r) => CircleMarker(
                          point: ringCenter,
                          radius: r,
                          useRadiusInMeter: true,
                          color: Colors.transparent,
                          borderColor: Colors.blue.withValues(alpha: 0.55),
                          borderStrokeWidth: 1.5,
                        ),
                      )
                      .toList(),
                ),
              if (_settings.ringPreset.radii.isNotEmpty)
                MarkerLayer(
                  markers: _settings.ringPreset.radii.map((r) {
                    final labelPos = _distanceCalc.offset(ringCenter, r, 0);
                    return Marker(
                      point: labelPos,
                      width: 54,
                      height: 20,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${r.toInt()} м',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              CircleLayer(
                circles: filteredSpots.where((s) => s.isPrivateCircle).map((s) {
                  final center = (s.publicLatitude != null &&
                          s.publicLongitude != null)
                      ? LatLng(s.publicLatitude!, s.publicLongitude!)
                      : s.displayPointFor(myId);
                  return CircleMarker(
                    point: center,
                    radius: 250,
                    useRadiusInMeter: true,
                    color: Colors.orange.withValues(alpha: 0.16),
                    borderColor: Colors.orange.withValues(alpha: 0.75),
                    borderStrokeWidth: 1.5,
                  );
                }).toList(),
              ),
              if (_loadedTrack != null && _loadedTrack!.points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _loadedTrack!.points,
                      color: Colors.deepPurpleAccent,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              if (_trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackPoints,
                      color: Colors.redAccent,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              if (_navTargetPoint != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [navOrigin, _navTargetPoint!],
                      color: Colors.amber.shade800,
                      strokeWidth: 3.5,
                      pattern: StrokePattern.dashed(segments: const [10, 8]),
                    ),
                  ],
                ),
              if (_rulerPoints.length >= 2)
                PolylineLayer(
                  polylines: [
