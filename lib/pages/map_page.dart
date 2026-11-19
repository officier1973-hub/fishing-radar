import 'dart:async';
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

  // Стартовый центр по умолчанию (Волга / Самара), пока не получен GPS
  LatLng _currentCenter = const LatLng(53.2001, 50.1500);
  LatLng? _myPosition;
  double? _myHeadingDeg;
  double _speedKmh = 0.0;
  double _mapRotationDeg = 0.0;
  bool _isMapReady = false;

  List<FishingSpot> _spots = [];
  MapLayerSettings _settings = const MapLayerSettings();

  // Активный записываемый трек
  final List<LatLng> _trackPoints = [];
  StreamSubscription<Position>? _trackSub;
  bool _isTracking = false;
  DateTime? _trackStartTime;
  double _trackDistanceMeters = 0.0;
  double _trackMaxSpeedKmh = 0.0;

  // Просматриваемый сохранённый трек
  BoatTrack? _loadedTrack;

  // Навигация к выбранной точке / «на берег»
  LatLng? _navTargetPoint;
  String? _navTargetLabel;

  // Инструмент «Линейка»
  bool _isRulerMode = false;
  final List<LatLng> _rulerPoints = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tileProvider = _createSafeTileProvider();
    ApiService.backendReadyNotifier.addListener(_onBackendReady);
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

  @override
  void dispose() {
    ApiService.backendReadyNotifier.removeListener(_onBackendReady);
    _trackSub?.cancel();
    _tileProvider.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _safeMove(LatLng center, double zoom) {
    if (!_isMapReady) return;
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
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
    } catch (_) {
      // Если GPS/настройки недоступны при старте, всё равно грузим карту и точки
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
    setState(() => _settings = next);
    _trackService.saveSettings(next);
  }

  Future<void> _goToMyLocation() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Включите GPS и разрешите доступ к геолокации'),
        ),
      );
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

    final ok = await _locationService.ensurePermission();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет разрешения на GPS для записи трека')),
      );
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

  Future<void> _openCreateSpot(LatLng point) async {
    final created = await Navigator.of(context).push<FishingSpot>(
      MaterialPageRoute(builder: (_) => ReportPage(initialPoint: point)),
    );
    if (created == null) return;

    final saved = await _apiService.createSpot(created);
    if (!mounted) return;
    setState(() => _spots.add(saved));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Точка сохранена на карту')),
    );
  }

  void _showSpotDetails(FishingSpot spot) {
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(spot.createdAt);
    final spotPoint = LatLng(spot.latitude, spot.longitude);
    final fromPoint = _myPosition ?? _currentCenter;
    final distMeters = _distanceCalc.as(LengthUnit.Meter, fromPoint, spotPoint);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
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
            Text('Рельеф дна: ${spot.bottomType}'),
            if (spot.fishWeightKg != null)
              Text('Вес улова: ${spot.fishWeightKg} кг'),
            Text('Расстояние: ${formatDistance(distMeters)}'),
            Text('Дата: $dateStr'),
            if (spot.isPrivateCircle)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Chip(
                  avatar: Icon(Icons.shield, size: 18),
                  label: Text('Зона «Круг доверия» (радиус 250 м)'),
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
          ],
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
    final ringCenter = _myPosition ?? _currentCenter;
    final filteredSpots = _spots
        .where((s) => _settings.depthFilter.matches(s.depthMeters))
        .toList();

    final baseUrl = _settings.baseMap == BaseMapType.satellite
        ? OfflineMapService.satelliteUrlTemplate
        : OfflineMapService.osmUrlTemplate;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fishing Radar'),
        actions: [
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
            tooltip: 'Слои, глубины и кольца',
            icon: const Icon(Icons.layers),
            onPressed: () => showLayersSheet(
              context: context,
              current: _settings,
              onChanged: _updateSettings,
            ),
          ),
          IconButton(
            tooltip: 'Обновить точки',
            icon: const Icon(Icons.refresh),
            onPressed: _loadSpots,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 13,
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
                  _openCreateSpot(point);
                }
              },
              onPositionChanged: (camera, _) {
                _currentCenter = camera.center;
                final rotDiff = (camera.rotation - _mapRotationDeg).abs();
                if (rotDiff > 1.0) {
                  setState(() => _mapRotationDeg = camera.rotation);
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
                    ...filteredSpots.map(
                      (s) => CircleMarker(
                        point: LatLng(s.latitude, s.longitude),
                        radius: 115,
                        useRadiusInMeter: true,
                        color: _depthColor(s.depthMeters).withValues(alpha: 0.11),
                        borderStrokeWidth: 0,
                      ),
                    ),
                    ...filteredSpots.map(
                      (s) => CircleMarker(
                        point: LatLng(s.latitude, s.longitude),
                        radius: 50,
                        useRadiusInMeter: true,
                        color: _depthColor(s.depthMeters).withValues(alpha: 0.22),
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
                          borderColor: Colors.blue.withValues(alpha: 0.50),
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
                            color: Colors.black.withValues(alpha: 0.55),
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
                circles: filteredSpots
                    .where((s) => s.isPrivateCircle)
                    .map(
                      (s) => CircleMarker(
                        point: LatLng(s.latitude, s.longitude),
                        radius: 250,
                        useRadiusInMeter: true,
                        color: Colors.orange.withValues(alpha: 0.16),
                        borderColor: Colors.orange.withValues(alpha: 0.7),
                        borderStrokeWidth: 1.5,
                      ),
                    )
                    .toList(),
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
                    Polyline(
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
                  ...filteredSpots.map(
                    (spot) => Marker(
                      point: LatLng(spot.latitude, spot.longitude),
                      width: 56,
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
                                color: _depthColor(spot.depthMeters),
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
                                  ? Icons.shield
                                  : Icons.location_on,
                              color: spot.isPrivateCircle
                                  ? Colors.orange
                                  : _depthColor(spot.depthMeters),
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                color: Colors.black.withValues(alpha: 0.80),
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
                if (_settings.showDepthZones)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _legendDot(Colors.teal, '<3м'),
                          const SizedBox(width: 8),
                          _legendDot(Colors.blue, '3–7м'),
                          const SizedBox(width: 8),
                          _legendDot(Colors.indigo, '7–12м'),
                          const SizedBox(width: 8),
                          _legendDot(Colors.deepPurple, '>12м'),
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
                          Text(
                            'Долгое нажатие — добавить точку',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (!_apiService.isBackendConfigured)
                          Text(
                            'Режим офлайн-кеша (Supabase не подключён)',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.orange[800]),
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
