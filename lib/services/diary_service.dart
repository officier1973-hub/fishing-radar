import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diary_entry.dart';

class DiaryStats {
  final int totalTrips;
  final double totalHours;
  final int totalCatchCount;
  final double totalWeightKg;

  const DiaryStats({
    required this.totalTrips,
    required this.totalHours,
    required this.totalCatchCount,
    required this.totalWeightKg,
  });
}

class DiaryService {
  static const String _tripsKey = 'fishing_diary_trips_v1';
  static const String _tackleKey = 'fishing_tackle_templates_v1';

  Future<List<FishingTripEntry>> loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tripsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final trips = list
          .map(
            (e) => FishingTripEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      trips.sort((a, b) => b.date.compareTo(a.date));
      return trips;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTrip(FishingTripEntry entry) async {
    final trips = await loadTrips();
    final idx = trips.indexWhere((t) => t.id == entry.id);
    if (idx != -1) {
      trips[idx] = entry;
    } else {
      trips.insert(0, entry);
    }
    trips.sort((a, b) => b.date.compareTo(a.date));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tripsKey,
      jsonEncode(trips.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> deleteTrip(String id) async {
    final trips = await loadTrips();
    trips.removeWhere((t) => t.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tripsKey,
      jsonEncode(trips.map((t) => t.toJson()).toList()),
    );
  }

  Future<List<TackleTemplate>> loadTackles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tackleKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final items = list
          .map(
            (e) => TackleTemplate.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTackle(TackleTemplate template) async {
    final items = await loadTackles();
    final idx = items.indexWhere((t) => t.id == template.id);
    if (idx != -1) {
      items[idx] = template;
    } else {
      items.insert(0, template);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tackleKey,
      jsonEncode(items.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> deleteTackle(String id) async {
    final items = await loadTackles();
    items.removeWhere((t) => t.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tackleKey,
      jsonEncode(items.map((t) => t.toJson()).toList()),
    );
  }

  DiaryStats computeStats(List<FishingTripEntry> trips) {
    var hours = 0.0;
    var count = 0;
    var weight = 0.0;
    for (final t in trips) {
      hours += t.durationHours;
      count += t.catchCount;
      weight += t.totalWeightKg;
    }
    return DiaryStats(
      totalTrips: trips.length,
      totalHours: hours,
      totalCatchCount: count,
      totalWeightKg: weight,
    );
  }
}
