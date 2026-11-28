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
import '../services/gpx_service.dart';
import '../services/location_service.dart';
import '../services/offline_map_service.dart';
import '../services/track_service.dart';
import '../services/waterway_service.dart';
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
  static const String _standardFallbackUrl =
      'https://tile.openstreetmap.de/{z}/{x}/{y}.png';
  static const String _satelliteFallbackUrl =
      'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const String _hybridTransportFallbackUrl =
      'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}';
  static const String _hybridLabelsFallbackUrl =
      'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  final MapController _mapController = MapController();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();
  final TrackService _trackService = TrackService();
  final GpxService _gpxService = GpxService();
  final OfflineMapService _offlineService = OfflineMapService();
  final WeatherService _weatherService = WeatherService();
  final WaterwayService _waterwayService = WaterwayService();
  final Distance _distanceCalc = const Distance();

  TileProvider? _activeMbtilesProvider;
  String? _activeMbtilesPathLoaded;
  TileProvider? _overlayMbtilesProvider;
  String? _overlayMbtilesPathLoaded;
  int _cacheEpoch = 0;

  LatLng _currentCenter = const LatLng(53.2001, 50.1500);
  double _currentZoom = 13.0;
  LatLng? _myPosition;
  double? _myHeadingDeg;
  double _speedKmh = 0.0;
  double _mapRotationDeg = 0.0;
  bool _isMapReady = false;

  List<FishingSpot> _spots = [];
  MapLayerSettings _settings = const MapLayerSettings();

  WaterwayOverlayData _waterwayData = WaterwayOverlayData.empty;
  bool _isLoadingWaterways = false;
  String? _waterwayStatus;
  Timer? _waterwayDebounce;
  int _waterwayRequestSeq = 0;

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
    ApiService.backendReadyNotifier.addListener(_onBackendReady);
    ApiService.pendingCountNotifier.addListener(_onStatusChanged);
    ApiService.lastErrorNotifier.addListener(_onStatusChanged);
    _initData();
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
    _waterwayDebounce?.cancel();
    _trackSub?.cancel();
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
    if (_settings.showSeamarks && _isMapReady) {
      _refreshWaterways();
    }
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
    final seamarksToggled = next.showSeamarks != _settings.showSeamarks;
    _syncMbtilesProviders(next);
    setState(() => _settings = next);
    _trackService.saveSettings(next);

    if (seamarksToggled) {
      if (next.showSeamarks) {
        _refreshWaterways();
      } else {
        _waterwayDebounce?.cancel();
        setState(() {
          _waterwayData = WaterwayOverlayData.empty;
          _isLoadingWaterways = false;
          _waterwayStatus = null;
        });
      }
    }
  }

  void _selectAndFitTrack(BoatTrack? track) {
    setState(() => _loadedTrack = track);
    if (track != null && track.points.length >= 2 && _isMapReady) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(track.points),
          padding: const EdgeInsets.all(48),
        ),
      );
    }
  }

  void _openGpxExchangeSheet() {
    showGpxExchangeSheet(
      context: context,
      gpxService: _gpxService,
      trackService: _trackService,
      apiService: _apiService,
      currentSpots: _spots,
      onSelectTrack: _selectAndFitTrack,
      onSpotsChanged: _loadSpots,
    );
  }

  String _shortWaterwayError(Object error) {
    if (error is HttpException) return 'ошибка (${error.message})';
    if (error is SocketException) return 'нет сети или сервер недоступен';
    if (error is TimeoutException) return 'таймаут ответа сервера';
    if (error is FormatException) return 'некорректный ответ сервера';
    return 'ошибка загрузки данных';
  }

  Future<void> _refreshWaterways() async {
    if (!_settings.showSeamarks || !_isMapReady) return;
    if (_currentZoom < 9.0) {
      if (!mounted) return;
      setState(() {
        _waterwayData = WaterwayOverlayData.empty;
        _isLoadingWaterways = false;
        _waterwayStatus = 'Фарватер: приблизьте карту (зум ≥ 9)';
      });
      return;
    }

    final bounds = _mapController.camera.visibleBounds;
    final reqId = ++_waterwayRequestSeq;
    if (mounted) {
      setState(() {
        _isLoadingWaterways = true;
        _waterwayStatus = 'Фарватер: загрузка судового хода и знаков...';
      });
    }

    try {
      final data = await _waterwayService.fetchForBounds(bounds);
      if (!mounted ||
          reqId != _waterwayRequestSeq ||
          !_settings.showSeamarks) {
        return;
      }
      setState(() {
        _waterwayData = data;
        _isLoadingWaterways = false;
        if (data.fairwayLines.isEmpty && data.marks.isEmpty) {
          _waterwayStatus =
              'Фарватер: в этом квадрате нет отмеченных знаков/хода';
        } else {
          final cacheSuffix = data.fromCache ? ' (кеш)' : '';
          _waterwayStatus =
              'Фарватер: линий ${data.fairwayLines.length}, '
              'знаков/слипов ${data.marks.length}$cacheSuffix';
        }
      });
    } catch (e) {
      if (!mounted || reqId != _waterwayRequestSeq) return;
      setState(() {
        _isLoadingWaterways = false;
        _waterwayStatus = 'Фарватер: ${_shortWaterwayError(e)}';
      });
    }
  }

  void _cycleBaseMap() {
    if (_activeMbtilesProvider != null) {
      _updateSettings(_settings.copyWith(clearActiveMbtiles: true));
      return;
    }
    final nextMode = switch (_settings.baseMap) {
      BaseMapType.standard => BaseMapType.satellite,
      BaseMapType.satellite => BaseMapType.hybrid,
      BaseMapType.hybrid => BaseMapType.standard,
    };
    _updateSettings(_settings.copyWith(baseMap: nextMode));
  }

  void _toggleSeamarks() {
    _updateSettings(_settings.copyWith(showSeamarks: !_settings.showSeamarks));
  }

  String _baseMapLabel() {
    if (_activeMbtilesProvider != null) return 'Офлайн';
    return switch (_settings.baseMap) {
      BaseMapType.standard => 'Карта',
      BaseMapType.satellite => 'Спутник',
      BaseMapType.hybrid => 'Гибрид',
    };
  }

  void _showWaterwayMarkDetails(WaterwayMark mark) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_waterwayMarkIcon(mark.kind), size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mark.title,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              if (mark.detail.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(mark.detail),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.navigation),
                  label: const Text('Проложить курс сюда'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _setNavTarget(mark.point, mark.title);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _waterwayMarkIcon(WaterwayMarkKind kind) {
    return switch (kind) {
      WaterwayMarkKind.buoy => Icons.change_history,
      WaterwayMarkKind.beacon => Icons.light_mode,
      WaterwayMarkKind.lock => Icons.water_damage,
      WaterwayMarkKind.dam => Icons.warning_amber_rounded,
      WaterwayMarkKind.slipway => Icons.directions_boat,
      WaterwayMarkKind.other => Icons.anchor,
    };
  }

  Color _waterwayMarkColor(WaterwayMark mark) {
    final d = mark.detail.toLowerCase();
    if (mark.kind == WaterwayMarkKind.buoy) {
      if (d.contains('red') || d.contains('красн')) return Colors.red.shade700;
      if (d.contains('green') || d.contains('зелен')) {
        return Colors.green.shade700;
      }
      return Colors.amber.shade800;
    }
    return switch (mark.kind) {
      WaterwayMarkKind.beacon => Colors.amber.shade800,
      WaterwayMarkKind.lock => Colors.indigo.shade700,
      WaterwayMarkKind.dam => Colors.deepOrange.shade700,
      WaterwayMarkKind.slipway => Colors.teal.shade700,
      _ => Colors.blueGrey.shade700,
    };
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
      _selectAndFitTrack(selectedTrack);
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
