import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../services/weather_service.dart';

Future<void> showWeatherAndBiteSheet({
  required BuildContext context,
  required WeatherService weatherService,
  required LatLng point,
  String? locationTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (_, scrollController) => WeatherForecastSheet(
        weatherService: weatherService,
        point: point,
        locationTitle: locationTitle,
        scrollController: scrollController,
      ),
    ),
  );
}

class WeatherForecastSheet extends StatefulWidget {
  final WeatherService weatherService;
  final LatLng point;
  final String? locationTitle;
  final ScrollController scrollController;

  const WeatherForecastSheet({
    super.key,
    required this.weatherService,
    required this.point,
    this.locationTitle,
    required this.scrollController,
  });

  @override
  State<WeatherForecastSheet> createState() => _WeatherForecastSheetState();
}

class _WeatherForecastSheetState extends State<WeatherForecastSheet> {
  int _selectedTab = 0; // 0 = Погода и клёв, 1 = Нерестовый календарь
  bool _loadingWeather = true;
  String? _weatherError;
  WeatherForecastData? _forecast;

  SpawningBanRegion? _selectedRegion;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final regionFuture = widget.weatherService.getSelectedBanRegion(
      lat: widget.point.latitude,
      lon: widget.point.longitude,
    );
    await _loadWeather();
    final region = await regionFuture;
    if (!mounted) return;
    setState(() => _selectedRegion = region);
  }

  Future<void> _loadWeather() async {
    setState(() {
      _loadingWeather = true;
      _weatherError = null;
    });
    try {
      final data = await widget.weatherService.fetchForecast(
        lat: widget.point.latitude,
        lon: widget.point.longitude,
      );
      if (!mounted) return;
      setState(() {
        _forecast = data;
        _loadingWeather = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingWeather = false;
        _weatherError =
            'Нет интернета и сохранённого прогноза для этой точки';
      });
    }
  }

  Color _biteColor(int score) {
    if (score >= 75) return Colors.green.shade700;
    if (score >= 55) return Colors.teal.shade700;
    if (score >= 38) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  String _formatDelta(double delta) {
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)} мм/6ч';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.locationTitle ?? 'Выбранная точка';
    final coords =
        '${widget.point.latitude.toStringAsFixed(4)}, '
        '${widget.point.longitude.toStringAsFixed(4)}';

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    coords,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Обновить погоду',
              onPressed: _loadingWeather ? null : _loadWeather,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment<int>(
              value: 0,
              icon: Icon(Icons.wb_sunny_outlined),
              label: Text('Погода и клёв'),
            ),
            ButtonSegment<int>(
              value: 1,
              icon: Icon(Icons.event_busy_outlined),
              label: Text('Нерест и запреты'),
            ),
          ],
          selected: {_selectedTab},
          onSelectionChanged: (sel) {
            setState(() => _selectedTab = sel.first);
          },
        ),
        const SizedBox(height: 14),
        if (_selectedTab == 0)
          _buildWeatherTab(context)
        else
          _buildSpawningTab(context),
      ],
    );
  }

  Widget _buildWeatherTab(BuildContext context) {
    if (_loadingWeather && _forecast == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_weatherError != null && _forecast == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.cloud_off, size: 36),
              const SizedBox(height: 8),
              Text(_weatherError!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loadWeather,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _forecast!;
    final biteColor = _biteColor(data.biteIndex);
    final windDirLabel = WeatherService.compassFromDegrees(data.windDirectionDeg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.isFromCache)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Chip(
              avatar: const Icon(Icons.offline_bolt, size: 18),
              label: Text(
                'Из кеша от ${DateFormat('dd.MM HH:mm').format(data.fetchedAt)}',
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: biteColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(color: biteColor, width: 2.5),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${data.biteIndex}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: biteColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '/100',
                        style: TextStyle(fontSize: 10, color: biteColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Индекс клёва: ${data.biteVerdict}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${data.temperatureC.toStringAsFixed(1)}°C '
                        '(ощущается ${data.apparentTemperatureC.toStringAsFixed(0)}°C) • '
                        '${WeatherService.describeWeatherCode(data.weatherCode)}',
                      ),
                      if (data.sunrise != null && data.sunset != null)
                        Text(
                          'Рассвет ${DateFormat('HH:mm').format(data.sunrise!)} • '
                          'Закат ${DateFormat('HH:mm').format(data.sunset!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.air, size: 18),
                          SizedBox(width: 6),
                          Text('Ветер', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${data.windSpeedMs.toStringAsFixed(1)} м/с ($windDirLabel)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        'Порывы до ${data.windGustsMs.toStringAsFixed(1)} м/с',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.speed, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Давление',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${data.pressureMmHg.round()} мм рт. ст.',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        'Тренд: ${_formatDelta(data.pressureDelta6hMmHg)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Разбор факторов клёва',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        ...data.biteFactors.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${f.score}/${f.maxScore}'),
                  ],
                ),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: f.maxScore > 0 ? f.score / f.maxScore : 0,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 2),
                Text(
                  f.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (data.nextHours.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Почасовой прогноз (24 ч)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.nextHours.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, idx) {
                final h = data.nextHours[idx];
                final c = _biteColor(h.biteIndex);
                return Container(
                  width: 84,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(h.time),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('${h.temperatureC.round()}°C'),
                      Text(
                        '${h.windSpeedMs.toStringAsFixed(0)} м/с ${WeatherService.compassFromDegrees(h.windDirectionDeg)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        '${h.pressureMmHg.round()} мм',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Клёв ${h.biteIndex}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: c,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSpawningTab(BuildContext context) {
    final region = _selectedRegion ?? WeatherService.spawningRegions.first;
    final now = DateTime.now();
    final isBanActive = region.isBanActiveOn(now);
    final statusText = isBanActive
        ? 'Действует нерестовый запрет (осталось ${region.daysUntilEnd(now)} дн.)'
        : 'Нерестового запрета нет (до начала ${region.daysUntilStart(now)} дн.)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: region.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Рыбохозяйственный регион / бассейн',
            border: OutlineInputBorder(),
          ),
          items: WeatherService.spawningRegions
              .map(
                (r) => DropdownMenuItem(
                  value: r.id,
                  child: Text(r.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (id) async {
            if (id == null) return;
            final found = WeatherService.spawningRegions.firstWhere(
              (r) => r.id == id,
            );
            setState(() => _selectedRegion = found);
            await widget.weatherService.saveSelectedBanRegion(id);
          },
        ),
        const SizedBox(height: 12),
        Card(
          color: isBanActive
              ? Colors.orange.withValues(alpha: 0.14)
              : Colors.green.withValues(alpha: 0.14),
          child: ListTile(
            leading: Icon(
              isBanActive ? Icons.warning_amber_rounded : Icons.check_circle,
              color: isBanActive ? Colors.orange.shade800 : Colors.green.shade700,
              size: 30,
            ),
            title: Text(
              statusText,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('Основное окно запрета: ${region.periodLabel}'),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Водоёмы',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(region.waterbodies),
                const Divider(height: 20),
                Text(
                  'Что разрешено в период запрета',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(region.allowedGear),
                const Divider(height: 20),
                Text(
                  'Важные уточнения',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(region.extraNotes),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Памятка: точные границы нерестовых участков и зимовальных ям проверяйте '
          'по актуальным правилам рыболовства вашего территориального управления.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
