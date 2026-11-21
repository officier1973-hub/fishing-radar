import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../models/fishing_spot.dart';

class ReportResult {
  final FishingSpot spot;
  final Uint8List? photoBytes;
  final String photoExt;

  const ReportResult({
    required this.spot,
    this.photoBytes,
    this.photoExt = 'jpg',
  });
}

class ReportPage extends StatefulWidget {
  final LatLng initialPoint;
  final FishingSpot? existingSpot;

  const ReportPage({
    super.key,
    required this.initialPoint,
    this.existingSpot,
  });

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _depthController;
  late final TextEditingController _speciesController;
  late final TextEditingController _weightController;
  late final TextEditingController _commentController;

  late String _bottomType;
  late bool _isPrivateCircle;

  Uint8List? _pickedPhotoBytes;
  String? _pickedPhotoPath;
  String _pickedPhotoExt = 'jpg';
  bool _removeExistingPhoto = false;

  static const _bottomOptions = [
    'Бровка / свал',
    'Яма',
    'Ракушечник',
    'Коряжник',
    'Ил / ровный стол',
    'Песок / камень',
  ];

  bool get _isEditing => widget.existingSpot != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existingSpot;
    _depthController = TextEditingController(
      text: e != null ? e.depthMeters.toString() : '4.5',
    );
    _speciesController = TextEditingController(
      text: e != null ? e.fishSpecies : 'Судак',
    );
    _weightController = TextEditingController(
      text: e?.fishWeightKg != null ? e!.fishWeightKg.toString() : '',
    );
    _commentController = TextEditingController(text: e?.comment ?? '');
    _bottomType = e?.bottomType ?? _bottomOptions.first;
    _isPrivateCircle = e?.isPrivateCircle ?? false;
    _pickedPhotoPath = e?.localPhotoPath;
  }

  @override
  void dispose() {
    _depthController.dispose();
    _speciesController.dispose();
    _weightController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 75,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final parts = file.name.split('.');
      final ext = parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
      if (!mounted) return;
      setState(() {
        _pickedPhotoBytes = bytes;
        _pickedPhotoPath = file.path;
        _pickedPhotoExt = ext;
        _removeExistingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось выбрать фото')),
      );
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final depth = double.parse(_depthController.text.replaceAll(',', '.'));
    final weightText = _weightController.text.trim().replaceAll(',', '.');
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);

    final base = widget.existingSpot;
    final spot = base != null
        ? base.copyWith(
            depthMeters: depth,
            bottomType: _bottomType,
            fishSpecies: _speciesController.text.trim(),
            fishWeightKg: weight,
            clearWeight: weight == null,
            comment: _commentController.text.trim(),
            isPrivateCircle: _isPrivateCircle,
            clearPhotoUrl: _removeExistingPhoto,
            localPhotoPath: _pickedPhotoPath,
            clearLocalPhotoPath: _removeExistingPhoto,
          )
        : FishingSpot(
            id: 'local-${DateTime.now().millisecondsSinceEpoch}',
            latitude: widget.initialPoint.latitude,
            longitude: widget.initialPoint.longitude,
            depthMeters: depth,
            bottomType: _bottomType,
            fishSpecies: _speciesController.text.trim(),
            fishWeightKg: weight,
            comment: _commentController.text.trim(),
            isPrivateCircle: _isPrivateCircle,
            localPhotoPath: _pickedPhotoPath,
            createdAt: DateTime.now(),
          );

    Navigator.of(context).pop(
      ReportResult(
        spot: spot,
        photoBytes: _pickedPhotoBytes,
        photoExt: _pickedPhotoExt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _bottomOptions.contains(_bottomType)
        ? _bottomOptions
        : [_bottomType, ..._bottomOptions];

    final existingUrl =
        _removeExistingPhoto ? null : widget.existingSpot?.photoUrl;
    final hasLocalFile = !_removeExistingPhoto &&
        _pickedPhotoBytes == null &&
        _pickedPhotoPath != null &&
        File(_pickedPhotoPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактировать точку' : 'Новая точка / отчёт'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.place),
                title: const Text('Координаты точки'),
                subtitle: Text(
                  '${widget.initialPoint.latitude.toStringAsFixed(5)}, '
                  '${widget.initialPoint.longitude.toStringAsFixed(5)}',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _depthController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Глубина (метры)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.water),
              ),
              validator: (v) {
                final val = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (val == null || val <= 0 || val > 200) {
                  return 'Укажите реальную глубину (0.1 – 200 м)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _bottomType,
              decoration: const InputDecoration(
                labelText: 'Структура дна / рельеф',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.layers),
              ),
              items: options
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _bottomType = v);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _speciesController,
              decoration: const InputDecoration(
                labelText: 'Вид рыбы',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.set_meal),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Укажите рыбу' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _weightController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Вес трофея, кг (необязательно)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.scale),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Заметка (приманка, время, погода)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Фото улова или приманки',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (_pickedPhotoBytes != null ||
                hasLocalFile ||
                existingUrl != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: _pickedPhotoBytes != null
                          ? Image.memory(_pickedPhotoBytes!, fit: BoxFit.cover)
                          : hasLocalFile
                              ? Image.file(
                                  File(_pickedPhotoPath!),
                                  fit: BoxFit.cover,
                                )
                              : Image.network(
                                  existingUrl!,
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
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() {
                        _pickedPhotoBytes = null;
                        _pickedPhotoPath = null;
                        _removeExistingPhoto = true;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Камера'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Галерея'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Круг доверия (скрыть точную точку)'),
              subtitle: const Text(
                'Другим рыбакам покажется смещённая зона радиусом 250 м; точные координаты видите только вы',
              ),
              value: _isPrivateCircle,
              onChanged: (v) => setState(() => _isPrivateCircle = v),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: Text(
                _isEditing ? 'Сохранить изменения' : 'Сохранить точку на карту',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
