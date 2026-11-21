import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/boat_track.dart';
import '../models/diary_entry.dart';
import '../services/diary_service.dart';
import '../services/track_service.dart';
import '../services/weather_service.dart';

class DiaryPage extends StatefulWidget {
  final LatLng initialCenter;

  const DiaryPage({
    super.key,
    required this.initialCenter,
  });

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage>
    with SingleTickerProviderStateMixin {
  final DiaryService _diaryService = DiaryService();
  final TrackService _trackService = TrackService();
  final WeatherService _weatherService = WeatherService();

  late final TabController _tabController;
  bool _isLoading = true;
  List<FishingTripEntry> _trips = [];
  List<TackleTemplate> _tackles = [];
  List<BoatTrack> _tracks = [];

  static const List<String> _tackleCategories = [
    'Спиннинг',
    'Фидер',
    'Поплавок',
    'Зимняя',
    'Троллинг',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final tripsFuture = _diaryService.loadTrips();
    final tacklesFuture = _diaryService.loadTackles();
    final tracksFuture = _trackService.loadTracks();

    final trips = await tripsFuture;
    final tackles = await tacklesFuture;
    final tracks = await tracksFuture;
    if (!mounted) return;
    setState(() {
      _trips = trips;
      _tackles = tackles;
      _tracks = tracks;
      _isLoading = false;
    });
  }

  Future<void> _addQuickPresetTackles() async {
    final now = DateTime.now();
    final presets = [
      TackleTemplate(
        id: 'preset-jig-${now.millisecondsSinceEpoch}',
        name: 'Джиг судак / окунь',
        category: 'Спиннинг',
        rod: '2.4 м, тест 7–28 г',
        reel: '3000',
        line: 'Шнур #1.0 PE',
        lure: 'Виброхвост 3.5" + чебурашка 16 г',
        createdAt: now,
      ),
      TackleTemplate(
        id: 'preset-feeder-${now.millisecondsSinceEpoch + 1}',
        name: 'Фидер река / лещ',
        category: 'Фидер',
        rod: '3.6 м, тест до 90 г',
        reel: '4000',
        line: 'Шнур 0.14 мм, поводок 0.12',
        lure: 'Кормушка 60 г, опарыш/мотыль',
        createdAt: now.subtract(const Duration(seconds: 1)),
      ),
    ];
    for (final p in presets) {
      await _diaryService.saveTackle(p);
    }
    await _loadAll();
  }

  Future<void> _openTripEditor({FishingTripEntry? existing}) async {
    final titleCtrl = TextEditingController(
      text: existing?.title ??
          'Выезд ${DateFormat('dd.MM').format(DateTime.now())}',
    );
    final waterCtrl = TextEditingController(text: existing?.waterbody ?? '');
    final hoursCtrl = TextEditingController(
      text: (existing?.durationHours ?? 4.0).toString(),
    );
    final countCtrl = TextEditingController(
      text: (existing?.catchCount ?? 0).toString(),
    );
    final weightCtrl = TextEditingController(
      text: existing != null && existing.totalWeightKg > 0
          ? existing.totalWeightKg.toString()
          : '',
    );
    final bestCtrl = TextEditingController(text: existing?.bestFish ?? '');
    final tackleCtrl = TextEditingController(text: existing?.tackleName ?? '');
    final weatherCtrl =
        TextEditingController(text: existing?.weatherSummary ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    var selectedDate = existing?.date ?? DateTime.now();
    var selectedTrackId = existing?.trackId;
    var selectedTrackName = existing?.trackName;
    int? biteIndex = existing?.biteIndex;
    var fetchingWeather = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Новый выезд' : 'Редактировать выезд',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Название выезда',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: waterCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Водоём / участок',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            DateFormat('dd.MM.yyyy').format(selectedDate),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setModalState(() => selectedDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: hoursCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Часов на воде',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: countCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Поймано, шт',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: weightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Общий вес, кг',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bestCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Лучший трофей (напр. Судак 2.4 кг)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_tackles.isNotEmpty) ...[
                    DropdownButtonFormField<String?>(
                      key: ValueKey('tackle-${tackleCtrl.text}'),
                      initialValue: _tackles.any((t) => t.name == tackleCtrl.text)
                          ? tackleCtrl.text
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Выбрать шаблон снасти',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Свой вариант / не выбрано'),
                        ),
                        ..._tackles.map(
                          (t) => DropdownMenuItem<String?>(
                            value: t.name,
                            child: Text(
                              '${t.name} (${t.lure.isNotEmpty ? t.lure : t.category})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() => tackleCtrl.text = v);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: tackleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Снасть / приманка',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_tracks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('track-$selectedTrackId'),
                      initialValue: _tracks.any((t) => t.id == selectedTrackId)
                          ? selectedTrackId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Привязать GPS-трек лодки',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Без привязки к треку'),
                        ),
                        ..._tracks.map(
                          (tr) => DropdownMenuItem<String?>(
                            value: tr.id,
                            child: Text(
                              tr.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (id) {
                        setModalState(() {
                          selectedTrackId = id;
                          selectedTrackName = id == null
                              ? null
                              : _tracks
                                  .firstWhere((t) => t.id == id)
                                  .name;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: weatherCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Погода / ветер / давление',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Подтянуть погоду сейчас',
                        onPressed: fetchingWeather
                            ? null
                            : () async {
                                setModalState(() => fetchingWeather = true);
                                try {
                                  final w = await _weatherService.fetchForecast(
                                    lat: widget.initialCenter.latitude,
                                    lon: widget.initialCenter.longitude,
                                  );
                                  final dir = WeatherService.compassFromDegrees(
                                    w.windDirectionDeg,
                                  );
                                  setModalState(() {
                                    weatherCtrl.text =
                                        '${w.temperatureC.round()}°C, '
                                        '${w.windSpeedMs.toStringAsFixed(1)} м/с $dir, '
                                        '${w.pressureMmHg.round()} мм';
                                    biteIndex = w.biteIndex;
                                    fetchingWeather = false;
                                  });
                                } catch (_) {
                                  setModalState(() => fetchingWeather = false);
                                }
                              },
                        icon: fetchingWeather
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wb_sunny_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Выводы и заметки по клёву',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Сохранить запись'),
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      final entry = FishingTripEntry(
        id: existing?.id ?? 'trip-${DateTime.now().millisecondsSinceEpoch}',
        title: titleCtrl.text.trim().isEmpty ? 'Выезд' : titleCtrl.text.trim(),
        waterbody: waterCtrl.text.trim(),
        date: selectedDate,
        durationHours:
            double.tryParse(hoursCtrl.text.replaceAll(',', '.')) ?? 0.0,
        catchCount: int.tryParse(countCtrl.text.trim()) ?? 0,
        totalWeightKg:
            double.tryParse(weightCtrl.text.replaceAll(',', '.')) ?? 0.0,
        bestFish: bestCtrl.text.trim(),
        tackleName: tackleCtrl.text.trim(),
        trackId: selectedTrackId,
        trackName: selectedTrackName,
        weatherSummary: weatherCtrl.text.trim(),
        biteIndex: biteIndex,
        notes: notesCtrl.text.trim(),
        createdAt: existing?.createdAt ?? DateTime.now(),
      );
      await _diaryService.saveTrip(entry);
      await _loadAll();
    }

    titleCtrl.dispose();
    waterCtrl.dispose();
    hoursCtrl.dispose();
    countCtrl.dispose();
    weightCtrl.dispose();
    bestCtrl.dispose();
    tackleCtrl.dispose();
    weatherCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _openTackleEditor({TackleTemplate? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final rodCtrl = TextEditingController(text: existing?.rod ?? '');
    final reelCtrl = TextEditingController(text: existing?.reel ?? '');
    final lineCtrl = TextEditingController(text: existing?.line ?? '');
    final lureCtrl = TextEditingController(text: existing?.lure ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var category = existing?.category ?? _tackleCategories.first;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Новый шаблон снасти' : 'Изменить снасть',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Название комплекта (напр. Джиг с лодки)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('cat-$category'),
                    initialValue: _tackleCategories.contains(category)
                        ? category
                        : _tackleCategories.first,
                    decoration: const InputDecoration(
                      labelText: 'Тип ловли',
                      border: OutlineInputBorder(),
                    ),
                    items: _tackleCategories
                        .map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModalState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: rodCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Удилище / тест',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: reelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Катушка',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: lineCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Шнур / леска',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lureCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Основная приманка / оснастка',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Заметка (проводка, поводок, вес)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Сохранить снасть'),
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      final item = TackleTemplate(
        id: existing?.id ?? 'tackle-${DateTime.now().millisecondsSinceEpoch}',
        name: nameCtrl.text.trim().isEmpty ? category : nameCtrl.text.trim(),
        category: category,
        rod: rodCtrl.text.trim(),
        reel: reelCtrl.text.trim(),
        line: lineCtrl.text.trim(),
        lure: lureCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
        createdAt: existing?.createdAt ?? DateTime.now(),
      );
      await _diaryService.saveTackle(item);
      await _loadAll();
    }

    nameCtrl.dispose();
    rodCtrl.dispose();
    reelCtrl.dispose();
    lineCtrl.dispose();
    lureCtrl.dispose();
    notesCtrl.dispose();
  }

  BoatTrack? _findTrackById(String? id) {
    if (id == null) return null;
    for (final t in _tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _diaryService.computeStats(_trips);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Личный дневник'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.menu_book), text: 'Журнал выездов'),
            Tab(icon: Icon(Icons.phishing), text: 'Мои снасти'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTripsTab(context, stats),
                _buildTacklesTab(context),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _openTripEditor();
          } else {
            _openTackleEditor();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(
          _tabController.index == 0 ? 'Новый выезд' : 'Новая снасть',
        ),
      ),
    );
  }

  Widget _buildTripsTab(BuildContext context, DiaryStats stats) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statCol('${stats.totalTrips}', 'Выездов'),
                _statCol('${stats.totalHours.toStringAsFixed(0)} ч', 'На воде'),
                _statCol('${stats.totalCatchCount}', 'Рыб'),
                _statCol('${stats.totalWeightKg.toStringAsFixed(1)} кг', 'Улов'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_trips.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.menu_book_outlined, size: 42),
                  const SizedBox(height: 10),
                  Text(
                    'Записей о выездах пока нет',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Фиксируйте водоёмы, рабочие снасти, погоду и привязывайте GPS-треки.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ..._trips.map((trip) {
            final linkedTrack = _findTrackById(trip.trackId);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trip.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          DateFormat('dd.MM.yyyy').format(trip.date),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (trip.waterbody.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        trip.waterbody,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '${trip.durationHours.toStringAsFixed(1)} ч',
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            'Улов: ${trip.catchCount} шт (${trip.totalWeightKg.toStringAsFixed(1)} кг)',
                          ),
                        ),
                        if (trip.biteIndex != null)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('Клёв: ${trip.biteIndex}/100'),
                          ),
                      ],
                    ),
                    if (trip.bestFish.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Трофей: ${trip.bestFish}'),
                      ),
                    if (trip.tackleName.isNotEmpty)
                      Text('Снасть: ${trip.tackleName}'),
                    if (trip.weatherSummary.isNotEmpty)
                      Text('Погода: ${trip.weatherSummary}'),
                    if (trip.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(trip.notes),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (linkedTrack != null)
                          TextButton.icon(
                            icon: const Icon(Icons.timeline, size: 18),
                            label: const Text('Трек на карту'),
                            onPressed: () =>
                                Navigator.of(context).pop(linkedTrack),
                          )
                        else if (trip.trackName != null)
                          Text(
                            'Трек: ${trip.trackName}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Редактировать',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openTripEditor(existing: trip),
                        ),
                        IconButton(
                          tooltip: 'Удалить',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _diaryService.deleteTrip(trip.id);
                            await _loadAll();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTacklesTab(BuildContext context) {
    if (_tackles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phishing_outlined, size: 44),
              const SizedBox(height: 10),
              Text(
                'Шаблонов снастей пока нет',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Сохраните рабочие комплекты, чтобы в один тап подставлять их в отчёты о клёве и выезды.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: _addQuickPresetTackles,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Добавить стартовые шаблоны'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: _tackles.length,
      itemBuilder: (_, idx) {
        final t = _tackles[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    t.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(t.category),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(t.summaryLine),
                if (t.reel.isNotEmpty) Text('Катушка: ${t.reel}'),
                if (t.notes.isNotEmpty) Text(t.notes),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openTackleEditor(existing: t),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _diaryService.deleteTackle(t.id);
                    await _loadAll();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statCol(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
