class TackleTemplate {
  final String id;
  final String name;
  final String category;
  final String rod;
  final String reel;
  final String line;
  final String lure;
  final String notes;
  final DateTime createdAt;

  const TackleTemplate({
    required this.id,
    required this.name,
    this.category = 'Спиннинг',
    this.rod = '',
    this.reel = '',
    this.line = '',
    this.lure = '',
    this.notes = '',
    required this.createdAt,
  });

  String get summaryLine {
    final parts = <String>[
      if (rod.trim().isNotEmpty) rod.trim(),
      if (line.trim().isNotEmpty) line.trim(),
      if (lure.trim().isNotEmpty) lure.trim(),
    ];
    return parts.isEmpty ? category : parts.join(' • ');
  }

  TackleTemplate copyWith({
    String? id,
    String? name,
    String? category,
    String? rod,
    String? reel,
    String? line,
    String? lure,
    String? notes,
    DateTime? createdAt,
  }) {
    return TackleTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      rod: rod ?? this.rod,
      reel: reel ?? this.reel,
      line: line ?? this.line,
      lure: lure ?? this.lure,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory TackleTemplate.fromJson(Map<String, dynamic> json) {
    return TackleTemplate(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Снасть').toString(),
      category: (json['category'] ?? 'Спиннинг').toString(),
      rod: (json['rod'] ?? '').toString(),
      reel: (json['reel'] ?? '').toString(),
      line: (json['line'] ?? '').toString(),
      lure: (json['lure'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'rod': rod,
      'reel': reel,
      'line': line,
      'lure': lure,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class FishingTripEntry {
  final String id;
  final String title;
  final String waterbody;
  final DateTime date;
  final double durationHours;
  final int catchCount;
  final double totalWeightKg;
  final String bestFish;
  final String tackleName;
  final String? trackId;
  final String? trackName;
  final String weatherSummary;
  final int? biteIndex;
  final String notes;
  final DateTime createdAt;

  const FishingTripEntry({
    required this.id,
    required this.title,
    required this.waterbody,
    required this.date,
    this.durationHours = 4.0,
    this.catchCount = 0,
    this.totalWeightKg = 0.0,
    this.bestFish = '',
    this.tackleName = '',
    this.trackId,
    this.trackName,
    this.weatherSummary = '',
    this.biteIndex,
    this.notes = '',
    required this.createdAt,
  });

  FishingTripEntry copyWith({
    String? id,
    String? title,
    String? waterbody,
    DateTime? date,
    double? durationHours,
    int? catchCount,
    double? totalWeightKg,
    String? bestFish,
    String? tackleName,
    String? trackId,
    bool clearTrack = false,
    String? trackName,
    String? weatherSummary,
    int? biteIndex,
    bool clearBiteIndex = false,
    String? notes,
    DateTime? createdAt,
  }) {
    return FishingTripEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      waterbody: waterbody ?? this.waterbody,
      date: date ?? this.date,
      durationHours: durationHours ?? this.durationHours,
      catchCount: catchCount ?? this.catchCount,
      totalWeightKg: totalWeightKg ?? this.totalWeightKg,
      bestFish: bestFish ?? this.bestFish,
      tackleName: tackleName ?? this.tackleName,
      trackId: clearTrack ? null : (trackId ?? this.trackId),
      trackName: clearTrack ? null : (trackName ?? this.trackName),
      weatherSummary: weatherSummary ?? this.weatherSummary,
      biteIndex: clearBiteIndex ? null : (biteIndex ?? this.biteIndex),
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory FishingTripEntry.fromJson(Map<String, dynamic> json) {
    return FishingTripEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Выезд').toString(),
      waterbody: (json['waterbody'] ?? '').toString(),
      date: DateTime.tryParse((json['date'] ?? '').toString()) ??
          DateTime.now(),
      durationHours: (json['duration_hours'] as num?)?.toDouble() ?? 0.0,
      catchCount: (json['catch_count'] as num?)?.toInt() ?? 0,
      totalWeightKg: (json['total_weight_kg'] as num?)?.toDouble() ?? 0.0,
      bestFish: (json['best_fish'] ?? '').toString(),
      tackleName: (json['tackle_name'] ?? '').toString(),
      trackId: json['track_id']?.toString(),
      trackName: json['track_name']?.toString(),
      weatherSummary: (json['weather_summary'] ?? '').toString(),
      biteIndex: (json['bite_index'] as num?)?.toInt(),
      notes: (json['notes'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'waterbody': waterbody,
      'date': date.toIso8601String(),
      'duration_hours': durationHours,
      'catch_count': catchCount,
      'total_weight_kg': totalWeightKg,
      'best_fish': bestFish,
      'tackle_name': tackleName,
      'track_id': trackId,
      'track_name': trackName,
      'weather_summary': weatherSummary,
      'bite_index': biteIndex,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
