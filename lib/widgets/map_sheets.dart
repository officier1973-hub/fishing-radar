import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/boat_track.dart';
import '../models/fishing_spot.dart';
import '../services/api_service.dart';
import '../services/gpx_service.dart';
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
  VoidCallback? onOpenGpx,
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
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: BaseMapType.standard,
                          icon: Icon(Icons.map, size: 17),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Карта', maxLines: 1),
                          ),
                        ),
                        ButtonSegment(
                          value: BaseMapType.satellite,
                          icon: Icon(Icons.satellite_alt, size: 17),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Спутник', maxLines: 1),
                          ),
                        ),
                        ButtonSegment(
                          value: BaseMapType.hybrid,
                          icon: Icon(Icons.layers, size: 17),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Гибрид', maxLines: 1),
                          ),
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
                  if (onOpenGpx != null) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.import_export),
                      title: const Text('Экспорт и импорт GPX'),
                      subtitle: const Text(
                        'Выгрузка и загрузка треков и точек клёва в .gpx',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onOpenGpx();
                      },
                    ),
                  ],
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
  required GpxService gpxService,
  required BoatTrack? activeLoadedTrack,
  required ValueChanged<BoatTrack?> onSelectTrack,
  VoidCallback? onOpenGpxSheet,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      String? statusMessage;
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
                  if (onOpenGpxSheet != null) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.import_export),
                        label: const Text('Экспорт / импорт GPX (треки и точки)'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onOpenGpxSheet();
                        },
                      ),
                    ),
                  ],
                  if (statusMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      statusMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  ],
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
                            'Нажмите кнопку маршрута справа, чтобы записать проход, или импортируйте .gpx.',
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
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Экспорт трека в GPX',
                                    icon: const Icon(
                                      Icons.file_download_outlined,
                                    ),
                                    onPressed: () async {
                                      try {
                                        final xml = gpxService.buildGpx(
                                          tracks: [track],
                                          documentName: track.name,
                                        );
                                        final saved =
                                            await gpxService.saveGpxFile(
                                          fileName: track.name,
                                          gpxContent: xml,
                                          dialogTitle: 'Экспорт трека в GPX',
                                        );
                                        if (!ctx.mounted) return;
                                        setSheetState(() {
                                          statusMessage = saved
                                              ? 'Трек «${track.name}» сохранён в .gpx'
                                              : 'Сохранение отменено.';
                                        });
                                      } catch (e) {
                                        if (!ctx.mounted) return;
                                        setSheetState(() {
                                          statusMessage =
                                              'Ошибка экспорта: $e';
                                        });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Удалить трек',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      await trackService.deleteTrack(track.id);
                                      if (isSelected) onSelectTrack(null);
                                      if (!ctx.mounted) return;
                                      setSheetState(() {});
                                    },
                                  ),
                                ],
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

Future<void> showGpxExchangeSheet({
  required BuildContext context,
  required GpxService gpxService,
  required TrackService trackService,
  required ApiService apiService,
  required List<FishingSpot> currentSpots,
  required ValueChanged<BoatTrack?> onSelectTrack,
  required Future<void> Function() onSpotsChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      var onlyMySpots = false;
      var busy = false;
      String? statusMessage;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final myId = apiService.currentUserId;
          final realSpots =
              currentSpots.where((s) => !s.id.startsWith('demo-')).toList();
          final exportSpots = onlyMySpots
              ? realSpots.where((s) => s.isOwnedBy(myId)).toList()
              : realSpots;

          Future<void> handleExport({
            required bool includeSpots,
            required bool includeTracks,
            required String baseFileName,
            required String docName,
          }) async {
            setSheetState(() {
              busy = true;
              statusMessage = null;
            });
            try {
              final tracks = includeTracks
                  ? await trackService.loadTracks()
                  : const <BoatTrack>[];
              final spotsToExport =
                  includeSpots ? exportSpots : const <FishingSpot>[];

              if (tracks.isEmpty && spotsToExport.isEmpty) {
                if (!ctx.mounted) return;
                setSheetState(() {
                  statusMessage = 'Нет данных для экспорта.';
                });
                return;
              }

              final xml = gpxService.buildGpx(
                tracks: tracks,
                spots: spotsToExport,
                currentUserId: myId,
                documentName: docName,
              );
              final dateTag = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
              final saved = await gpxService.saveGpxFile(
                fileName: '${baseFileName}_$dateTag.gpx',
                gpxContent: xml,
              );
              if (!ctx.mounted) return;
              setSheetState(() {
                statusMessage = saved
                    ? 'Файл GPX сохранён (точек: ${spotsToExport.length}, треков: ${tracks.length}).'
                    : 'Сохранение отменено.';
              });
            } catch (e) {
              if (!ctx.mounted) return;
              setSheetState(() => statusMessage = 'Ошибка экспорта: $e');
            } finally {
              if (ctx.mounted) {
                setSheetState(() => busy = false);
              }
            }
          }

          Future<void> handleImport() async {
            setSheetState(() {
              busy = true;
              statusMessage = null;
            });
            try {
              final picked = await gpxService.pickAndParseGpxFile();
              if (!ctx.mounted) return;
              if (picked == null) {
                setSheetState(() => busy = false);
                return;
              }

              final (fileName, parsed) = picked;
              if (parsed.isEmpty) {
                setSheetState(() {
                  busy = false;
                  statusMessage =
                      'В файле «$fileName» не найдено треков и точек.';
                });
                return;
              }

              var importTracks = parsed.tracks.isNotEmpty;
              var importSpots = parsed.spots.isNotEmpty;
              var protectSpots = true;

              final confirmed = await showDialog<bool>(
                context: ctx,
                builder: (dCtx) => StatefulBuilder(
                  builder: (dCtx, setDialogState) {
                    return AlertDialog(
                      title: Text('Импорт $fileName'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Найдено треков: ${parsed.tracks.length}\n'
                              'Найдено точек: ${parsed.spots.length}',
                            ),
                            const SizedBox(height: 10),
                            if (parsed.tracks.isNotEmpty)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Импортировать треки (${parsed.tracks.length})',
                                ),
                                value: importTracks,
                                onChanged: (v) => setDialogState(
                                  () => importTracks = v ?? false,
                                ),
                              ),
                            if (parsed.spots.isNotEmpty) ...[
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Импортировать точки (${parsed.spots.length})',
                                ),
                                value: importSpots,
                                onChanged: (v) => setDialogState(
                                  () => importSpots = v ?? false,
                                ),
                              ),
                              if (importSpots)
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Круг доверия (250 м)'),
                                  subtitle: const Text(
                                    'Скрыть точные координаты от посторонних',
                                  ),
                                  value: protectSpots,
                                  onChanged: (v) => setDialogState(
                                    () => protectSpots = v,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dCtx).pop(false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: (!importTracks && !importSpots)
                              ? null
                              : () => Navigator.of(dCtx).pop(true),
                          child: const Text('Импортировать'),
                        ),
                      ],
                    );
                  },
                ),
              );

              if (confirmed != true) {
                if (ctx.mounted) setSheetState(() => busy = false);
                return;
              }

              var addedTracks = 0;
              var addedSpots = 0;

              if (importTracks && parsed.tracks.isNotEmpty) {
                addedTracks = await trackService.saveTracksBatch(parsed.tracks);
                onSelectTrack(parsed.tracks.first);
              }

              if (importSpots && parsed.spots.isNotEmpty) {
                final preparedSpots = parsed.spots
                    .map((s) => s.copyWith(isPrivateCircle: protectSpots))
                    .toList();
                addedSpots = await apiService.importSpotsBatch(preparedSpots);
                await onSpotsChanged();
              }

              if (!ctx.mounted) return;
              setSheetState(() {
                statusMessage =
                    'Импортировано из «$fileName»: треков — $addedTracks, '
                    'точек — $addedSpots'
                    '${(addedTracks == 0 && addedSpots == 0) ? ' (дубликаты пропущены)' : ''}.';
              });
            } catch (e) {
              if (!ctx.mounted) return;
              setSheetState(() => statusMessage = 'Ошибка импорта: $e');
            } finally {
              if (ctx.mounted) {
                setSheetState(() => busy = false);
              }
            }
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Экспорт и импорт GPX',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Универсальный формат .gpx для эхолотов, навигаторов и резервного копирования треков и точек.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Импорт файла .gpx',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Выбрать .gpx файл с телефона'),
                      onPressed: busy ? null : handleImport,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Text(
                    'Экспорт в .gpx',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Экспортировать только мои точки'),
                    subtitle: const Text(
                      'Чужие точки Круга доверия всегда выгружаются со смещением 250 м',
                    ),
                    value: onlyMySpots,
                    onChanged: busy
                        ? null
                        : (v) => setSheetState(() => onlyMySpots = v),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.place_outlined, size: 18),
                          label: Text('Точки (${exportSpots.length})'),
                          onPressed: busy
                              ? null
                              : () => handleExport(
                                    includeSpots: true,
                                    includeTracks: false,
                                    baseFileName: 'fishradar_spots',
                                    docName: 'FishRadar Spots',
                                  ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.route, size: 18),
                          label: const Text('Все треки'),
                          onPressed: busy
                              ? null
                              : () => handleExport(
                                    includeSpots: false,
                                    includeTracks: true,
                                    baseFileName: 'fishradar_tracks',
                                    docName: 'FishRadar Tracks',
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Экспортировать всё (точки + треки)'),
                      onPressed: busy
                          ? null
                          : () => handleExport(
                                includeSpots: true,
                                includeTracks: true,
                                baseFileName: 'fishradar_backup',
                                docName: 'FishRadar Backup',
                              ),
                    ),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      statusMessage!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
