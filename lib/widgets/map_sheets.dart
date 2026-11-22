import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

          final activeFile = local.activeMbtilesPath?.split('/').last;
          final overlayFile = local.overlayMbtilesPath?.split('/').last;

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
                  if (activeFile != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.offline_pin, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Офлайн-подложка: $activeFile',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => update(
                              local.copyWith(clearActiveMbtiles: true),
                            ),
                            child: const Text('Онлайн'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    'Онлайн-подложка',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<BaseMapType>(
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: BaseMapType.standard,
                          icon: Icon(Icons.map, size: 18),
                          label: Text('Карта'),
                        ),
                        ButtonSegment(
                          value: BaseMapType.satellite,
                          icon: Icon(Icons.satellite_alt, size: 18),
                          label: Text('Спутник'),
                        ),
                        ButtonSegment(
                          value: BaseMapType.hybrid,
                          icon: Icon(Icons.layers, size: 18),
                          label: Text('Гибрид'),
                        ),
                      ],
                      selected: {local.baseMap},
                      onSelectionChanged: (s) => update(
                        local.copyWith(
                          baseMap: s.first,
                          clearActiveMbtiles: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (overlayFile != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.layers),
                      title: Text('Доп. слой: $overlayFile'),
                      subtitle: const Text('Подключённый пакет .mbtiles'),
                      trailing: TextButton(
                        onPressed: () => update(
                          local.copyWith(clearOverlayMbtiles: true),
                        ),
                        child: const Text('Снять'),
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Водные знаки и фарватер'),
                    subtitle: const Text(
                      'Бакены, створы и судовой ход (на судоходных реках при зуме 9–17)',
                    ),
                    value: local.showSeamarks,
                    onChanged: (v) => update(local.copyWith(showSeamarks: v)),
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
  required MapLayerSettings currentSettings,
  required ValueChanged<MapLayerSettings> onSettingsChanged,
  VoidCallback? onCacheCleared,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      var settings = currentSettings;
      var reloadTick = 0;
      var isDownloading = false;
      var isCancelled = false;
      var receivedBytes = 0;
      var totalBytes = -1;
      String? downloadingName;
      String? statusMessage;

      Future<void> startUrlDownload(
        StateSetter setSheetState,
        String url,
        String name,
      ) async {
        setSheetState(() {
          isDownloading = true;
          isCancelled = false;
          receivedBytes = 0;
          totalBytes = -1;
          downloadingName = name;
          statusMessage = null;
        });

        try {
          final info = await offlineService.downloadMbtilesFromUrl(
            url: url,
            fileName: name,
            isCancelled: () => isCancelled,
            onProgress: (rec, tot) {
              if (!ctx.mounted) return;
              setSheetState(() {
                receivedBytes = rec;
                totalBytes = tot;
              });
            },
          );
          if (!ctx.mounted) return;
          setSheetState(() {
            reloadTick++;
            if (info == null) {
              statusMessage = 'Скачивание отменено.';
            } else {
              statusMessage =
                  'Файл «${info.fileName}» (${OfflineMapService.formatFileSize(info.sizeBytes)}) готов. '
                  'Нажмите «Основа» или «Слой» ниже.';
            }
          });
        } catch (e) {
          if (!ctx.mounted) return;
          setSheetState(() => statusMessage = 'Ошибка: $e');
        } finally {
          if (ctx.mounted) {
            setSheetState(() => isDownloading = false);
          }
        }
      }

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          void updateSettings(MapLayerSettings next) {
            setSheetState(() => settings = next);
            onSettingsChanged(next);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Офлайн-карты',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Авто-кеш просмотра (30 дней)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Всё, что вы пролистали на карте и спутнике при интернете, '
                          'сохраняется в памяти телефона на 30 дней.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Очистить авто-кеш'),
                          onPressed: isDownloading
                              ? null
                              : () async {
                                  await offlineService.clearCache();
                                  onCacheCleared?.call();
                                  if (!ctx.mounted) return;
                                  setSheetState(() {
                                    statusMessage = 'Авто-кеш очищен.';
                                  });
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Карты регионов (.mbtiles)',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Скачанный пакет .mbtiles работает на 100% без интернета — '
                    'можно выбрать с телефона, по ссылке или из облака.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('С телефона'),
                          onPressed: isDownloading
                              ? null
                              : () async {
                                  try {
                                    final picked = await FilePicker.pickFile();
                                    if (picked == null) return;
                                    final imported = await offlineService
                                        .importPickedMbtiles(picked);
                                    if (!ctx.mounted) return;
                                    setSheetState(() {
                                      reloadTick++;
                                      statusMessage =
                                          'Добавлена карта «${imported.fileName}» '
                                          '(${OfflineMapService.formatFileSize(imported.sizeBytes)}).';
                                    });
                                  } catch (e) {
                                    if (!ctx.mounted) return;
                                    setSheetState(() {
                                      statusMessage = 'Ошибка импорта: $e';
                                    });
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.link),
                          label: const Text('По ссылке'),
                          onPressed: isDownloading
                              ? null
                              : () async {
                                  final urlCtrl = TextEditingController();
                                  final nameCtrl = TextEditingController(
                                    text: 'region.mbtiles',
                                  );
                                  final ok = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) => AlertDialog(
                                      title: const Text('Скачать .mbtiles'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextField(
                                            controller: urlCtrl,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Прямая ссылка (https://...)',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          TextField(
                                            controller: nameCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Имя файла',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dCtx).pop(false),
                                          child: const Text('Отмена'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(dCtx).pop(true),
                                          child: const Text('Скачать'),
                                        ),
                                      ],
                                    ),
                                  );
                                  final url = urlCtrl.text.trim();
                                  final name = nameCtrl.text.trim();
                                  urlCtrl.dispose();
                                  nameCtrl.dispose();
                                  if (ok == true &&
                                      url.isNotEmpty &&
                                      ctx.mounted) {
                                    await startUrlDownload(
                                      setSheetState,
                                      url,
                                      name,
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: totalBytes > 0
                          ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            totalBytes > 0
                                ? 'Скачивание $downloadingName: '
                                    '${OfflineMapService.formatFileSize(receivedBytes)} из '
                                    '${OfflineMapService.formatFileSize(totalBytes)}'
                                : 'Скачивание $downloadingName: '
                                    '${OfflineMapService.formatFileSize(receivedBytes)}',
                          ),
                        ),
                        TextButton(
                          onPressed: () => isCancelled = true,
                          child: const Text('Отмена'),
                        ),
                      ],
                    ),
                  ],
                  if (statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      statusMessage!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FutureBuilder<List<LocalMbtilesInfo>>(
                    key: ValueKey('local-$reloadTick'),
                    future: offlineService.listLocalMbtiles(),
                    builder: (_, snap) {
                      final files = snap.data ?? [];
                      if (files.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'На телефоне пока нет файлов .mbtiles.',
                            style: TextStyle(fontSize: 13),
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Подключённые на телефоне:',
                            style: Theme.of(ctx).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          ...files.map((item) {
                            final isBase =
                                settings.activeMbtilesPath == item.path;
                            final isOverlay =
                                settings.overlayMbtilesPath == item.path;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  8,
                                  8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.map_outlined,
                                            size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${item.fileName} • ${OfflineMapService.formatFileSize(item.sizeBytes)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Удалить файл',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                          ),
                                          onPressed: isDownloading
                                              ? null
                                              : () async {
                                                  await offlineService
                                                      .deleteLocalMbtiles(
                                                    item.path,
                                                  );
                                                  if (isBase || isOverlay) {
                                                    updateSettings(
                                                      settings.copyWith(
                                                        clearActiveMbtiles:
                                                            isBase,
                                                        clearOverlayMbtiles:
                                                            isOverlay,
                                                      ),
                                                    );
                                                  }
                                                  if (!ctx.mounted) return;
                                                  setSheetState(
                                                      () => reloadTick++);
                                                },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        FilterChip(
                                          label: const Text('Основа карты'),
                                          selected: isBase,
                                          onSelected: (v) => updateSettings(
                                            settings.copyWith(
                                              activeMbtilesPath:
                                                  v ? item.path : null,
                                              clearActiveMbtiles: !v,
                                            ),
                                          ),
                                        ),
                                        FilterChip(
                                          label: const Text('Верхний слой'),
                                          selected: isOverlay,
                                          onSelected: (v) => updateSettings(
                                            settings.copyWith(
                                              overlayMbtilesPath:
                                                  v ? item.path : null,
                                              clearOverlayMbtiles: !v,
                                            ),
                                          ),
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
                    },
                  ),
                  FutureBuilder<List<CloudMbtilesInfo>>(
                    key: ValueKey('cloud-$reloadTick'),
                    future: offlineService.listCloudMbtiles(),
                    builder: (_, snap) {
                      final cloudFiles = snap.data ?? [];
                      if (cloudFiles.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          Text(
                            'Доступно в облаке (Supabase):',
                            style: Theme.of(ctx).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          ...cloudFiles.map((cf) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.cloud_download_outlined),
                              title: Text(cf.name),
                              subtitle: cf.sizeBytes > 0
                                  ? Text(
                                      OfflineMapService.formatFileSize(
                                        cf.sizeBytes,
                                      ),
                                    )
                                  : null,
                              trailing: FilledButton.tonal(
                                onPressed: isDownloading
                                    ? null
                                    : () => startUrlDownload(
                                          setSheetState,
                                          cf.downloadUrl,
                                          cf.name,
                                        ),
                                child: const Text('Скачать'),
                              ),
                            );
                          }),
                        ],
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
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final track = tracks[index];
                            final isSelected =
                                activeLoadedTrack?.id == track.id;
                            final date =
                                DateFormat('dd.MM HH:mm').format(track.startedAt);
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
