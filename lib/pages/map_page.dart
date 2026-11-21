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
import '../services/weather_service.dart';
import '../widgets/map_sheets.dart';
import '../widgets/weather_sheet.dart';
import 'auth_page.dart';
import 'chat_page.dart';
import 'diary_page.dart';
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
  final WeatherService _weatherService = WeatherService();
  final Distance _distanceCalc = const Distance();

  late TileProvider _onlineTileProvider;
  TileProvider? _activeMbtilesProvider;
  String? _activeMbtilesPathLoaded;
  TileProvider? _overlayMbtilesProvider;
  String? _overlayMbtilesPathLoaded;

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
    _onlineTileProvider = _createSafeOnlineProvider();
    ApiService.backendReadyNotifier.addListener(_onBackendReady);
    ApiService.pendingCountNotifier.addListener(_onStatusChanged);
    ApiService.lastErrorNotifier.addListener(_onStatusChanged);
    _initData();
  }

  TileProvider _createSafeOnlineProvider() {
    try {
      return _offlineService.createTileProvider();
    } catch (_) {
      return NetworkTileProvider();
    }
  }

  void _syncMbtilesProviders(MapLayerSettings next) {
    if (next.activeMbtilesPath != _activeMbtilesPathLoaded) {
      _activeMbtilesProvider?.dispose();
      _activeMbtilesProvider = null;
      _activeMbtilesPathLoaded = null;

      final p = next.activeMbtilesPath;
      if (p != null && File(p).existsSync()) {
        try {
          _activeMbtilesProvider = _offlineService.createMbtilesTileProvider(p);
          _activeMbtilesPathLoaded = p;
        } catch (_) {
          _activeMbtilesProvider = null;
          _activeMbtilesPathLoaded = null;
        }
      }
    }

    if (next.overlayMbtilesPath != _overlayMbtilesPathLoaded) {
      _overlayMbtilesProvider?.dispose();
      _overlayMbtilesProvider = null;
      _overlayMbtilesPathLoaded = null;

      final p = next.overlayMbtilesPath;
      if (p != null && File(p).existsSync()) {
        try {
          _overlayMbtilesProvider =
              _offlineService.createMbtilesTileProvider(p);
          _overlayMbtilesPathLoaded = p;
        } catch (_) {
          _overlayMbtilesProvider = null;
          _overlayMbtilesPathLoaded = null;
        }
      }
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
    _onlineTileProvider.dispose();
    _activeMbtilesProvider?.dispose();
    _overlayMbtilesProvider?.dispose();
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

  Future<void> _initData() async {
    try {
      final savedSettings = await _trackService.loadSettings();
      _syncMbtilesProviders(savedSettings);
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
    _syncMbtilesProviders(next);
    setState(() => _settings = next);
    _trackService.saveSettings(next);
  }

  void _openWeatherSheet(LatLng point, {String? title}) {
    showWeatherAndBiteSheet(
      context: context,
      weatherService: _weatherService,
      point: point,
      locationTitle: title,
    );
  }

  Future<void> _openDiary() async {
    final selectedTrack = await Navigator.of(context).push<BoatTrack>(
      MaterialPageRoute(
        builder: (_) => DiaryPage(
          initialCenter: _myPosition ?? _currentCenter,
        ),
      ),
    );
    if (selectedTrack != null && mounted) {
      setState(() => _loadedTrack = selectedTrack);
      if (selectedTrack.points.length >= 2 && _isMapReady) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(selectedTrack.points),
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    }
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
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Погода, клёв и запреты здесь'),
              subtitle: const Text('Ветер, давление, индекс клёва для этой точки'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openWeatherSheet(point, title: 'Прогноз в точке карты');
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
                  : Image.network(
                      url!,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
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
                          : Image.network(
                              spot.photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: Colors.black12,
                                alignment: Alignment.center,
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image_outlined),
                                    SizedBox(height: 4),
                                    Text('Фото недоступно офлайн'),
                                  ],
                                ),
                              ),
                            ),
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
                    avatar: Icon(
                      spot.isTrustedFriend ? Icons.verified_user : Icons.shield,
                      size: 18,
                    ),
                    label: Text(
                      isMine
                          ? 'Круг доверия: вы видите точную точку'
                          : spot.isTrustedFriend
                              ? 'Круг доверия: друг открыл вам точную точку'
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: const Text('Погода и индекс клёва в точке'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _openWeatherSheet(
                      spotPoint,
                      title: '${spot.fishSpecies} • ${spot.depthMeters} м',
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
    if (depth < 3) return Colors.green.shade600;
    if (depth < 7) return Colors.blue.shade700;
    if (depth < 12) return Colors.indigo.shade800;
    return Colors.purple.shade800;
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

    final activeMbtilesName = _activeMbtilesPathLoaded?.split('/').last;

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
            tooltip: 'Офлайн-карты',
            icon: Icon(
              _activeMbtilesProvider != null || _overlayMbtilesProvider != null
                  ? Icons.offline_pin
                  : Icons.cloud_download_outlined,
            ),
            onPressed: () => showOfflineCacheSheet(
              context: context,
              offlineService: _offlineService,
              currentSettings: _settings,
              onSettingsChanged: _updateSettings,
              onCacheCleared: () {
                final old = _onlineTileProvider;
                setState(() => _onlineTileProvider = _createSafeOnlineProvider());
                old.dispose();
              },
            ),
          ),
          IconButton(
            tooltip: 'Слои и фильтры',
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
                _currentZoom = camera.zoom;
                final rotDiff = (camera.rotation - _mapRotationDeg).abs();
                if (rotDiff > 1.0) {
                  setState(() => _mapRotationDeg = camera.rotation);
                }
              },
            ),
            children: [
              if (_activeMbtilesProvider != null)
                TileLayer(
                  key: ValueKey('mbtiles-base-$_activeMbtilesPathLoaded'),
                  tileProvider: _activeMbtilesProvider!,
                  maxNativeZoom: 18,
                )
              else
                TileLayer(
                  key: ValueKey('online-base-${_settings.baseMap.name}'),
                  urlTemplate: baseUrl,
                  userAgentPackageName: 'ru.fishingradar.app',
                  tileProvider: _onlineTileProvider,
                  maxNativeZoom: 19,
                ),
              if (_overlayMbtilesProvider != null)
                TileLayer(
                  key: ValueKey('mbtiles-overlay-$_overlayMbtilesPathLoaded'),
                  tileProvider: _overlayMbtilesProvider!,
                  maxNativeZoom: 18,
                ),
              if (_settings.showSeamarks)
                TileLayer(
                  urlTemplate: OfflineMapService.seamarkUrlTemplate,
                  userAgentPackageName: 'ru.fishingradar.app',
                  tileProvider: _onlineTileProvider,
                  maxNativeZoom: 18,
                ),
              if (_settings.ringPreset.radii.isNotEmpty)
                CircleLayer<Object>(
                  circles: _settings.ringPreset.radii
                      .map(
                        (r) => CircleMarker<Object>(
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
              CircleLayer<Object>(
                circles: filteredSpots.where((s) => s.isPrivateCircle).map((s) {
                  final center = (s.publicLatitude != null &&
                          s.publicLongitude != null)
                      ? LatLng(s.publicLatitude!, s.publicLongitude!)
                      : s.displayPointFor(myId);
                  return CircleMarker<Object>(
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
                PolylineLayer<Object>(
                  polylines: <Polyline<Object>>[
                    Polyline<Object>(
                      points: _loadedTrack!.points,
                      color: Colors.deepPurpleAccent,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              if (_trackPoints.length >= 2)
                PolylineLayer<Object>(
                  polylines: <Polyline<Object>>[
                    Polyline<Object>(
                      points: _trackPoints,
                      color: Colors.redAccent,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              if (_navTargetPoint != null)
                PolylineLayer<Object>(
                  polylines: <Polyline<Object>>[
                    Polyline<Object>(
                      points: [navOrigin, _navTargetPoint!],
                      color: Colors.amber.shade800,
                      strokeWidth: 3.5,
                      pattern: StrokePattern.dashed(segments: const [10, 8]),
                    ),
                  ],
                ),
              if (_rulerPoints.length >= 2)
                PolylineLayer<Object>(
                  polylines: <Polyline<Object>>[
                    Polyline<Object>(
                      points: _rulerPoints,
                      color: Colors.cyan.shade700,
                      strokeWidth: 3.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_myPosition != null)
                    Marker(
                      point: _myPosition!,
                      width: 36,
                      height: 36,
                      child: _myHeadingDeg != null
                          ? Transform.rotate(
                              angle: _myHeadingDeg! * math.pi / 180,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.navigation,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                            ),
                    ),
                  if (_navTargetPoint != null)
                    Marker(
                      point: _navTargetPoint!,
                      width: 34,
                      height: 34,
                      child: const Icon(
                        Icons.flag_circle,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),
                  ..._rulerPoints.map(
                    (p) => Marker(
                      point: p,
                      width: 14,
                      height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.cyan.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
                  ...filteredSpots.map((spot) {
                    final pt = spot.displayPointFor(myId);
                    final color = _depthColor(spot.depthMeters);
                    return Marker(
                      point: pt,
                      width: 58,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showSpotDetails(spot),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${spot.depthMeters.toStringAsFixed(1)}м',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Icon(
                              spot.isPrivateCircle
                                  ? (spot.isTrustedFriend
                                      ? Icons.verified_user
                                      : Icons.shield)
                                  : Icons.location_on,
                              color: spot.isPrivateCircle
                                  ? (spot.isTrustedFriend
                                      ? Colors.teal
                                      : Colors.orange)
                                  : color,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const Scalebar(
                alignment: Alignment.topRight,
                padding: EdgeInsets.fromLTRB(0, 12, 12, 0),
              ),
            ],
          ),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          if (_navTargetPoint != null &&
              navDistanceMeters != null &&
              navBearingDeg != null)
            Positioned(
              top: 12,
              left: 12,
              right: 96,
              child: Card(
                color: Colors.black.withValues(alpha: 0.82),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Transform.rotate(
                        angle: navBearingDeg * math.pi / 180,
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.amber,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _navTargetLabel ?? 'Цель',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${formatDistance(navDistanceMeters)} • '
                              '${navBearingDeg.round()}° (${_compassDirection(navBearingDeg)})',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: _clearNavTarget,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isRulerMode)
            Positioned(
              top: _navTargetPoint != null ? 82 : 12,
              left: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.straighten, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _rulerPoints.length < 2
                            ? 'Тапайте по карте для замера'
                            : 'Замер: ${formatDistance(_rulerTotalMeters)} (${_rulerPoints.length} т.)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_rulerPoints.isNotEmpty) ...[
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Отменить точку',
                          icon: const Icon(Icons.undo, size: 18),
                          onPressed: () =>
                              setState(() => _rulerPoints.removeLast()),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Сбросить',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => setState(() => _rulerPoints.clear()),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _legendDot(Colors.green.shade600, '<3м'),
                        const SizedBox(width: 8),
                        _legendDot(Colors.blue.shade700, '3–7м'),
                        const SizedBox(width: 8),
                        _legendDot(Colors.indigo.shade800, '7–12м'),
                        const SizedBox(width: 8),
                        _legendDot(Colors.purple.shade800, '>12м'),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (activeMbtilesName != null)
                          Text(
                            'Офлайн-карта: $activeMbtilesName',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        if (_isTracking) ...[
                          Text(
                            'Трек: ${formatDistance(_trackDistanceMeters)} • '
                            '${_speedKmh.toStringAsFixed(1)} км/ч',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (_trackPoints.isNotEmpty)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.home, size: 16),
                              label: const Text('К старту (на берег)'),
                              onPressed: () => _setNavTarget(
                                _trackPoints.first,
                                'Старт трека (берег)',
                              ),
                            ),
                        ] else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Долгое нажатие — точка или курс',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: _loadSpots,
                                child: const Icon(Icons.refresh, size: 17),
                              ),
                            ],
                          ),
                        if (_pendingSyncCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: _loadSpots,
                              child: Text(
                                'Ожидают отправки: $_pendingSyncCount т. (нажмите для повтора)',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: Colors.orange[800]),
                              ),
                            ),
                          ),
                        if (_syncStatusNote != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 250),
                            child: Text(
                              _syncStatusNote!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: Colors.red[700]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mapRotationDeg.abs() > 2.0) ...[
            FloatingActionButton.small(
              heroTag: 'compass',
              tooltip: 'Север вверх',
              onPressed: () {
                _mapController.rotate(0);
                setState(() => _mapRotationDeg = 0.0);
              },
              child: const Icon(Icons.explore),
            ),
            const SizedBox(height: 10),
          ],
          FloatingActionButton.small(
            heroTag: 'diary',
            tooltip: 'Личный дневник и снасти',
            onPressed: _openDiary,
            child: const Icon(Icons.menu_book_outlined),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'weather',
            tooltip: 'Погода, индекс клёва и запреты',
            onPressed: () => _openWeatherSheet(
              _myPosition ?? _currentCenter,
              title: _myPosition != null
                  ? 'Погода рядом со мной'
                  : 'Погода в районе карты',
            ),
            child: const Icon(Icons.wb_sunny_outlined),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'ruler',
            tooltip: _isRulerMode ? 'Выключить линейку' : 'Линейка расстояний',
            backgroundColor: _isRulerMode ? Colors.cyan : null,
            foregroundColor: _isRulerMode ? Colors.white : null,
            onPressed: () => setState(() => _isRulerMode = !_isRulerMode),
            child: const Icon(Icons.straighten),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'gps',
            tooltip: 'Моё местоположение',
            onPressed: _goToMyLocation,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'track',
            tooltip: _isTracking ? 'Остановить трек' : 'Записать трек лодки',
            backgroundColor: _isTracking ? Colors.red : null,
            foregroundColor: _isTracking ? Colors.white : null,
            onPressed: _toggleTrackRecording,
            child: Icon(_isTracking ? Icons.stop : Icons.route),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'add',
            tooltip: 'Добавить точку',
            onPressed: () => _openCreateSpot(_myPosition ?? _currentCenter),
            child: const Icon(Icons.add_location_alt),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
