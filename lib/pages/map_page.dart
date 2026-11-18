import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/fishing_spot.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
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

  // Стартовый центр по умолчанию (Волга / Самара), пока не получен GPS
  LatLng _currentCenter = const LatLng(53.2001, 50.1500);
  LatLng? _myPosition;
  double _speedKmh = 0.0;

  List<FishingSpot> _spots = [];
  final List<LatLng> _trackPoints = [];
  StreamSubscription<Position>? _trackSub;

  bool _isTracking = false;
  bool _showDistanceRings = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos != null) {
      _myPosition = LatLng(pos.latitude, pos.longitude);
      _currentCenter = _myPosition!;
      _mapController.move(_currentCenter, 14);
    }
    await _loadSpots();
  }

  Future<void> _loadSpots() async {
    setState(() => _isLoading = true);
    final spots = await _apiService.getSpots(
      lat: _currentCenter.latitude,
      lon: _currentCenter.longitude,
    );
    if (!mounted) return;
    setState(() {
      _spots = spots;
      _isLoading = false;
    });
  }

  Future<void> _goToMyLocation() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Включите GPS и разрешите доступ к геолокации')),
      );
      return;
    }
    final point = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _myPosition = point;
      _currentCenter = point;
    });
    _mapController.move(point, 15);
  }

  Future<void> _toggleTrackRecording() async {
    if (_isTracking) {
      await _trackSub?.cancel();
      _trackSub = null;
      setState(() {
        _isTracking = false;
        _speedKmh = 0.0;
      });
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
      if (_myPosition != null) _trackPoints.add(_myPosition!);
    });

    _trackSub = _locationService.getPositionStream().listen((pos) {
      final point = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _myPosition = point;
        _speedKmh = (pos.speed >= 0 ? pos.speed : 0) * 3.6;
        _trackPoints.add(point);
      });
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
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
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Рельеф дна: ${spot.bottomType}'),
            if (spot.fishWeightKg != null)
              Text('Вес улова: ${spot.fishWeightKg} кг'),
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
          ],
        ),
      ),
    );
  }

  Color _depthColor(double depth) {
    if (depth < 3) return Colors.teal;
    if (depth < 7) return Colors.blue;
    return Colors.indigo;
  }

  @override
  Widget build(BuildContext context) {
    final ringCenter = _myPosition ?? _currentCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fishing Radar'),
        actions: [
          IconButton(
            tooltip: 'Кольца расстояний (50/100/200м)',
            icon: Icon(
              _showDistanceRings ? Icons.radar : Icons.radar_outlined,
              color: _showDistanceRings ? Colors.blue : null,
            ),
            onPressed: () =>
                setState(() => _showDistanceRings = !_showDistanceRings),
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
              onLongPress: (_, point) => _openCreateSpot(point),
              onPositionChanged: (camera, _) {
                _currentCenter = camera.center;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ru.fishingradar.app',
                maxNativeZoom: 19,
              ),
              if (_showDistanceRings)
                CircleLayer(
                  circles: [50.0, 100.0, 200.0]
                      .map(
                        (r) => CircleMarker(
                          point: ringCenter,
                          radius: r,
                          useRadiusInMeter: true,
                          color: Colors.transparent,
                          borderColor: Colors.blue.withValues(alpha: 0.45),
                          borderStrokeWidth: 1.5,
                        ),
                      )
                      .toList(),
                ),
              // Круги доверия для приватных точек (радиус 250 м)
              CircleLayer(
                circles: _spots
                    .where((s) => s.isPrivateCircle)
                    .map(
                      (s) => CircleMarker(
                        point: LatLng(s.latitude, s.longitude),
                        radius: 250,
                        useRadiusInMeter: true,
                        color: Colors.orange.withValues(alpha: 0.18),
                        borderColor: Colors.orange.withValues(alpha: 0.7),
                        borderStrokeWidth: 1.5,
                      ),
                    )
                    .toList(),
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
              MarkerLayer(
                markers: [
                  if (_myPosition != null)
                    Marker(
                      point: _myPosition!,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ..._spots.map(
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
            ],
          ),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          Positioned(
            left: 12,
            bottom: 20,
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isTracking
                          ? 'Трек: ${_trackPoints.length} т. • ${_speedKmh.toStringAsFixed(1)} км/ч'
                          : 'Долгое нажатие на карту — добавить точку',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!_apiService.isBackendConfigured)
                      Text(
                        'Режим офлайн-кеша (API_BASE_URL не задан)',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.orange[800]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
}
