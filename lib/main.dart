import 'package:flutter/material.dart';
import 'pages/map_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FishingRadarApp());
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
