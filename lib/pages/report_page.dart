import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/fishing_spot.dart';

class ReportPage extends StatefulWidget {
  final LatLng initialPoint;

  const ReportPage({super.key, required this.initialPoint});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _formKey = GlobalKey<FormState>();
  final _depthController = TextEditingController(text: '4.5');
  final _speciesController = TextEditingController(text: 'Судак');
  final _weightController = TextEditingController();
  final _commentController = TextEditingController();

  String _bottomType = 'Бровка / свал';
  bool _isPrivateCircle = false;

  static const _bottomOptions = [
    'Бровка / свал',
    'Яма',
    'Ракушечник',
    'Коряжник',
    'Ил / ровный стол',
    'Песок / камень',
  ];

  @override
  void dispose() {
    _depthController.dispose();
    _speciesController.dispose();
    _weightController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final depth = double.parse(_depthController.text.replaceAll(',', '.'));
    final weightText = _weightController.text.trim().replaceAll(',', '.');
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);

    final spot = FishingSpot(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      latitude: widget.initialPoint.latitude,
      longitude: widget.initialPoint.longitude,
      depthMeters: depth,
      bottomType: _bottomType,
      fishSpecies: _speciesController.text.trim(),
      fishWeightKg: weight,
      comment: _commentController.text.trim(),
      isPrivateCircle: _isPrivateCircle,
      createdAt: DateTime.now(),
    );

    Navigator.of(context).pop(spot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая точка / отчёт')),
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
              items: _bottomOptions
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
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Круг доверия (скрыть точную точку)'),
              subtitle: const Text(
                'Публично покажется зона радиусом 250 м, а не точные координаты',
              ),
              value: _isPrivateCircle,
              onChanged: (v) => setState(() => _isPrivateCircle = v),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text('Сохранить точку на карту'),
            ),
          ],
        ),
      ),
    );
  }
}
