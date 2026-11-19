import 'dart:async';
import 'package:flutter/material.dart';
import 'pages/map_page.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF041E2B),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Ошибка интерфейса:\n${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  };

  runApp(const FishingRadarApp());
  unawaited(ApiService.initSupabase());
}

class FishingRadarApp extends StatelessWidget {
  const FishingRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fishing Radar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D77)),
        useMaterial3: true,
      ),
      home: const MapPage(),
    );
  }
}
