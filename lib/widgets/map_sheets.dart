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
  const popularFish = ['', 'Судак', 'Щука', 'Окунь', 'Лещ', 'Карп'];

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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Слои карты и фильтры',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Подложка карты',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<BaseMapType>(
                    segments: const [
                      ButtonSegment(
                        value: BaseMapType.standard,
                        icon: Icon(Icons.map),
                        label: Text('Карта'),
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
                    title: const Text('Водные знаки и фарватер'),
                    subtitle: const Text('Бакены, створы и судовой ход'),
                    value: local.showSeamarks,
                    onChanged: (v) => update(local.copyWith(showSeamarks: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Зоны глубин (по точкам)'),
                    subtitle: const Text('Цветные ореолы глубин на водоёме'),
                    value: local.showDepthZones,
                    onChanged: (v) => update(local.copyWith(showDepthZones: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Тепловая карта клёва'),
                    subtitle: const Text('Подсвечивает горячие зоны уловов'),
                    value: local.showHeatmap,
                    onChanged: (v) => update(local.copyWith(showHeatmap: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Только мои точки'),
                    subtitle: const Text('Скрыть чужие отчёты на карте'),
                    value: local.onlyMySpots,
                    onChanged: (v) => update(local.copyWith(onlyMySpots: v)),
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
                    'Фильтр по глубине',
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
                  const SizedBox(height: 14),
                  Text(
                    'Фильтр по рыбе',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: popularFish.map((fish) {
                      final label = fish.isEmpty ? 'Вся рыба' : fish;
                      return ChoiceChip(
                        label: Text(label),
                        selected: local.fishFilter.toLowerCase() ==
                            fish.toLowerCase(),
                        onSelected: (_) =>
                            update(local.copyWith(fishFilter: fish)),
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
  VoidCallback? onCacheCleared,
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
      var saved = 0;
      var cacheCheckTick = 0;
      String? statusMessage;

      final url = baseMap == BaseMapType.satellite
          ? OfflineMapService.satelliteUrlTemplate
          : OfflineMapService.standardUrlTemplate;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final maxZoom = detailedZoom ? 15 : 14;
          const minZoom = 12;

          final estimated = offlineService.estimateTileCount(
            bounds: visibleBounds,
            minZoom: minZoom,
            maxZoom: maxZoom,
          );
          final capped = estimated > OfflineMapService.maxTilesPerDownload;
          final plannedCount =
              capped ? OfflineMapService.maxTilesPerDownload : estimated;

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
                    'Нажмите «Скачать область» перед выходом на воду. Проверить работу '
                    'можно, включив «Режим полёта» на телефоне и полистав карту.',
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<(int, int)>(
                    key: ValueKey('$cacheCheckTick-$detailedZoom'),
                    future: offlineService.countCachedTiles(
                      urlTemplate: url,
                      bounds: visibleBounds,
                      minZoom: minZoom,
                      maxZoom: maxZoom,
                    ),
                    builder: (_, snap) {
                      if (!snap.hasData) {
                        return const SizedBox.shrink();
                      }
                      final (cached, all) = snap.data!;
                      final pct = all > 0 ? ((cached / all) * 100).round() : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Chip(
                          avatar: Icon(
                            pct == 100 ? Icons.check_circle : Icons.sd_storage,
                            size: 18,
                          ),
                          label: Text(
                            'В памяти телефона для этого экрана: $cached из $all ($pct%)',
                          ),
                        ),
                      );
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Высокая детализация (зум 12–15)'),
                    subtitle: const Text('Выше точность берега, но больше фрагментов'),
                    value: detailedZoom,
                    onChanged: isDownloading
                        ? null
                        : (v) => setSheetState(() => detailedZoom = v),
                  ),
                  Text(
                    capped
                        ? 'К загрузке: $plannedCount фрагментов (лимит за 1 раз — приблизьте карту для деталей)'
                        : 'К загрузке: $plannedCount фрагментов (≈ ${(plannedCount * 0.025).toStringAsFixed(1)} МБ)',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0,
                    ),
                    const SizedBox(height: 6),
                    Text('Обработано: $done из $total • сохранено: $saved'),
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
                              total = plannedCount;
                              saved = 0;
                              statusMessage = null;
                            });

                            try {
                              final result = await offlineService.downloadRegion(
                                urlTemplate: url,
                                bounds: visibleBounds,
                                minZoom: minZoom,
                                maxZoom: maxZoom,
                                isCancelled: () => isCancelled,
                                onProgress: (d, t, s) {
                                  if (!ctx.mounted) return;
                                  setSheetState(() {
                                    done = d;
                                    total = t;
                                    saved = s;
                                  });
                                },
                              );

                              if (!ctx.mounted) return;
                              setSheetState(() {
                                cacheCheckTick++;
                                if (isCancelled) {
                                  statusMessage =
                                      'Остановлено: сохранено ${result.saved} из ${result.total}.';
                                } else if (result.saved == 0 && result.total > 0) {
                                  statusMessage =
                                      'Не удалось скачать карту — проверьте интернет.';
                                } else if (result.failed > 0) {
                                  statusMessage =
                                      'Сохранено ${result.saved} из ${result.total} '
                                      '(пропущено ${result.failed} — нажмите ещё раз для докачки).';
                                } else {
                                  statusMessage =
                                      'Готово! Сохранены все ${result.saved} из ${result.total} фрагментов.';
                                }
                              });
                            } catch (e) {
                              if (!ctx.mounted) return;
                              setSheetState(() {
                                statusMessage = 'Ошибка загрузки: $e';
                              });
                            } finally {
                              if (ctx.mounted) {
                                setSheetState(() => isDownloading = false);
                              }
                            }
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
                                onCacheCleared?.call();
                                if (!ctx.mounted) return;
                                setSheetState(() {
                                  cacheCheckTick++;
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
