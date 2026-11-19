import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import '../models/boat_track.dart';
import '../services/offline_map_service.dart';
import '../services/track_service.dart';

String formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(2)} км';
  }
  return '${meters.round()} м';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$hч $mм' : '$m:$s';
}

Future<void> showLayersSheet({
  required BuildContext context,
  required MapLayerSettings current,
  required ValueChanged<MapLayerSettings> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      var local = current;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          void update(MapLayerSettings next) {
            setSheetState(() => local = next);
            onChanged(next);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Слои карты и радар',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Базовая карта',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<BaseMapType>(
                    segments: const [
                      ButtonSegment(
                        value: BaseMapType.osm,
                        icon: Icon(Icons.map),
                        label: Text('Схема OSM'),
                      ),
                      ButtonSegment(
                        value: BaseMapType.satellite,
                        icon: Icon(Icons.satellite_alt),
                        label: Text('Спутник'),
                      ),
                    ],
                    selected: {local.baseMap},
                    onSelectionChanged: (s) =>
                        update(local.copyWith(baseMap: s.first)),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Навигация OpenSeaMap'),
                    subtitle: const Text('Бакены, створы, судовой ход'),
                    value: local.showSeamarks,
                    onChanged: (v) => update(local.copyWith(showSeamarks: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Зоны глубин (по отчётам)'),
                    subtitle: const Text('Цветовые ореолы глубин на водоёме'),
                    value: local.showDepthZones,
                    onChanged: (v) => update(local.copyWith(showDepthZones: v)),
                  ),
                  const Divider(),
                  Text(
                    'Кольца расстояний',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: RingPreset.values.map((preset) {
                      return ChoiceChip(
                        label: Text(preset.label),
                        selected: local.ringPreset == preset,
                        onSelected: (_) =>
                            update(local.copyWith(ringPreset: preset)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Фильтр точек по глубине',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: DepthFilter.values.map((filter) {
                      return ChoiceChip(
                        label: Text(filter.label),
                        selected: local.depthFilter == filter,
                        onSelected: (_) =>
                            update(local.copyWith(depthFilter: filter)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showOfflineCacheSheet({
  required BuildContext context,
  required OfflineMapService offlineService,
  required LatLngBounds visibleBounds,
  required BaseMapType baseMap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      var detailedZoom = false;
      var isDownloading = false;
      var isCancelled = false;
      var done = 0;
      var total = 0;
      String? statusMessage;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final maxZoom = detailedZoom ? 15 : 14;
          final minZoom = 12;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Офлайн-карта района',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Просмотренные участки сохраняются на 30 дней автоматически. '
                    'Здесь можно заранее скачать текущий экран перед выходом на воду.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Высокая детализация (зум 12–15)'),
                    subtitle: const Text('Выше точность берега, но больше тайлов'),
                    value: detailedZoom,
                    onChanged: isDownloading
                        ? null
                        : (v) => setSheetState(() => detailedZoom = v),
                  ),
                  FutureBuilder<int>(
                    future: offlineService.estimateTileCount(
                      bounds: visibleBounds,
                      minZoom: minZoom,
                      maxZoom: maxZoom,
                    ),
                    builder: (context, snapshot) {
                      final est = snapshot.data ?? 0;
                      final capped = est > OfflineMapService.maxTilesPerDownload;
                      final count = capped
                          ? OfflineMapService.maxTilesPerDownload
                          : est;
                      return Text(
                        capped
                            ? 'Тайлов к загрузке: $count (лимит за 1 раз, приблизьте карту для деталей)'
                            : 'Тайлов к загрузке: $count (≈ ${(count * 0.025).toStringAsFixed(1)} МБ)',
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      );
                    },
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: total > 0 ? done / total : null,
                    ),
                    const SizedBox(height: 6),
                    Text('Загружено: $done из $total'),
                  ],
                  if (statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      statusMessage!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.primary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: Icon(isDownloading ? Icons.close : Icons.download),
                          label: Text(
                            isDownloading ? 'Отменить' : 'Скачать область',
                          ),
                          onPressed: () async {
                            if (isDownloading) {
                              isCancelled = true;
                              return;
                            }
                            setSheetState(() {
                              isDownloading = true;
                              isCancelled = false;
                              done = 0;
                              total = 0;
                              statusMessage = null;
                            });
                            final url = baseMap == BaseMapType.satellite
                                ? OfflineMapService.satelliteUrlTemplate
                                : OfflineMapService.osmUrlTemplate;

                            final loaded = await offlineService.downloadRegion(
                              urlTemplate: url,
                              bounds: visibleBounds,
                              minZoom: minZoom,
                              maxZoom: maxZoom,
                              isCancelled: () => isCancelled,
                              onProgress: (d, t) {
                                if (!ctx.mounted) return;
                                setSheetState(() {
                                  done = d;
                                  total = t;
                                });
                              },
                            );

                            if (!ctx.mounted) return;
                            setSheetState(() {
                              isDownloading = false;
                              statusMessage = isCancelled
                                  ? 'Загрузка остановлена ($loaded тайлов в кеше).'
                                  : 'Готово! В офлайн-кеше сохранено $loaded тайлов.';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Очистить'),
                        onPressed: isDownloading
                            ? null
                            : () async {
                                await offlineService.clearCache();
                                if (!ctx.mounted) return;
                                setSheetState(() {
                                  statusMessage = 'Кеш карт очищен.';
                                });
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showSavedTracksSheet({
  required BuildContext context,
  required TrackService trackService,
  required BoatTrack? activeLoadedTrack,
  required ValueChanged<BoatTrack?> onSelectTrack,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Сохранённые треки лодки',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                      ),
                      if (activeLoadedTrack != null)
                        TextButton(
                          onPressed: () {
                            onSelectTrack(null);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Скрыть'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<BoatTrack>>(
                    future: trackService.loadTracks(),
                    builder: (context, snapshot) {
                      final tracks = snapshot.data ?? [];
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (tracks.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            'Пока нет сохранённых треков.\n'
                            'Нажмите кнопку маршрута справа, чтобы записать проход.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 340),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: tracks.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final track = tracks[index];
                            final isSelected = activeLoadedTrack?.id == track.id;
                            final date = DateFormat('dd.MM HH:mm')
                                .format(track.startedAt);
                            return ListTile(
                              leading: Icon(
                                Icons.route,
                                color: isSelected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : null,
                              ),
                              title: Text(track.name),
                              subtitle: Text(
                                '$date • ${formatDistance(track.distanceMeters)} • '
                                '${formatDuration(track.duration)} • '
                                'ср. ${track.avgSpeedKmh.toStringAsFixed(1)} км/ч',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await trackService.deleteTrack(track.id);
                                  if (isSelected) onSelectTrack(null);
                                  setSheetState(() {});
                                },
                              ),
                              onTap: () {
                                onSelectTrack(track);
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
