import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class HourlyWeatherPoint {
  final DateTime time;
  final double temperatureC;
  final double pressureMmHg;
  final double windSpeedMs;
  final double windGustsMs;
  final double windDirectionDeg;
  final int precipitationProb;
  final int cloudCover;
  final int weatherCode;
  final int biteIndex;

  const HourlyWeatherPoint({
    required this.time,
    required this.temperatureC,
    required this.pressureMmHg,
    required this.windSpeedMs,
    required this.windGustsMs,
    required this.windDirectionDeg,
    required this.precipitationProb,
    required this.cloudCover,
    required this.weatherCode,
    required this.biteIndex,
  });
}

class BiteFactor {
  final String title;
  final String detail;
  final int score;
  final int maxScore;

  const BiteFactor({
    required this.title,
    required this.detail,
    required this.score,
    required this.maxScore,
  });
}

class WeatherForecastData {
  final double latitude;
  final double longitude;
  final DateTime fetchedAt;
  final bool isFromCache;
  final double temperatureC;
  final double apparentTemperatureC;
  final int humidityPercent;
  final double pressureMmHg;
  final double pressureDelta6hMmHg;
  final double windSpeedMs;
  final double windGustsMs;
  final double windDirectionDeg;
  final int cloudCover;
  final int weatherCode;
  final DateTime? sunrise;
  final DateTime? sunset;
  final int biteIndex;
  final String biteVerdict;
  final List<BiteFactor> biteFactors;
  final List<HourlyWeatherPoint> nextHours;

  const WeatherForecastData({
    required this.latitude,
    required this.longitude,
    required this.fetchedAt,
    required this.isFromCache,
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.humidityPercent,
    required this.pressureMmHg,
    required this.pressureDelta6hMmHg,
    required this.windSpeedMs,
    required this.windGustsMs,
    required this.windDirectionDeg,
    required this.cloudCover,
    required this.weatherCode,
    this.sunrise,
    this.sunset,
    required this.biteIndex,
    required this.biteVerdict,
    required this.biteFactors,
    required this.nextHours,
  });
}

class SpawningBanRegion {
  final String id;
  final String name;
  final String waterbodies;
  final int startMonth;
  final int startDay;
  final int endMonth;
  final int endDay;
  final String allowedGear;
  final String extraNotes;
  final double centerLat;
  final double centerLon;

  const SpawningBanRegion({
    required this.id,
    required this.name,
    required this.waterbodies,
    required this.startMonth,
    required this.startDay,
    required this.endMonth,
    required this.endDay,
    required this.allowedGear,
    required this.extraNotes,
    required this.centerLat,
    required this.centerLon,
  });

  bool isBanActiveOn(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final start = DateTime(date.year, startMonth, startDay);
    final end = DateTime(date.year, endMonth, endDay);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  int daysUntilStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    var start = DateTime(date.year, startMonth, startDay);
    if (d.isAfter(start)) {
      start = DateTime(date.year + 1, startMonth, startDay);
    }
    return start.difference(d).inDays;
  }

  int daysUntilEnd(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, endMonth, endDay);
    if (d.isAfter(end)) return 0;
    return end.difference(d).inDays + 1;
  }

  String get periodLabel =>
      '${startDay.toString().padLeft(2, '0')}.${startMonth.toString().padLeft(2, '0')}'
      ' – '
      '${endDay.toString().padLeft(2, '0')}.${endMonth.toString().padLeft(2, '0')}';
}

class WeatherService {
  static const String _cachePrefix = 'weather_cache_v1_';
  static const String _banRegionKey = 'selected_ban_region_v1';
  static const double _hpaToMmHg = 0.75006168;

  static const List<SpawningBanRegion> spawningRegions = [
    SpawningBanRegion(
      id: 'samara_volga',
      name: 'Самарская обл. / Средняя Волга',
      waterbodies: 'Волга, Куйбышевское и Саратовское вдхр., Сок, Самара',
      startMonth: 4,
      startDay: 20,
      endMonth: 6,
      endDay: 10,
      allowedGear:
          'С берега 1 поплавочной или донной удочкой (до 2 крючков) вне мест нереста.',
      extraNotes:
          'На Саратовском и Куйбышевском вдхр. ловля с лодки и спиннингом в запрет ограничена; действуют отдельные запреты на зимовальных ямах.',
      centerLat: 53.20,
      centerLon: 50.15,
    ),
    SpawningBanRegion(
      id: 'tatarstan_kama',
      name: 'Татарстан / Кама и Нижнекамское вдхр.',
      waterbodies: 'Кама, Волга, Вятка, Свияга, Нижнекамское вдхр.',
      startMonth: 4,
      startDay: 25,
      endMonth: 6,
      endDay: 5,
      allowedGear:
          'Только с берега 1 поплавочной или донной удочкой (не более 2 крючков).',
      extraNotes:
          'Запрещён выход на маломерных судах с целью рыбалки и ловля на спиннинг в нерестовый период.',
      centerLat: 55.79,
      centerLon: 49.12,
    ),
    SpawningBanRegion(
      id: 'moscow_oka',
      name: 'Москва, МО / Ока и Верхняя Волга',
      waterbodies: 'Москва-река, Ока, Клязьма, Истринское, Можайское, Рузское вдхр.',
      startMonth: 4,
      startDay: 1,
      endMonth: 6,
      endDay: 10,
      allowedGear:
          '1 поплавочной или донной удочкой с берега (до 2 крючков) вне нерестовых участков.',
      extraNotes:
          'Дополнительно: круглогодичный или сезонный запрет на налима и на зимовальных ямах (с 1 октября по 30 апреля).',
      centerLat: 55.75,
      centerLon: 37.62,
    ),
    SpawningBanRegion(
      id: 'lower_volga',
      name: 'Нижняя Волга / Астраханская обл.',
      waterbodies: 'Волга, Ахтуба, раскаты и дельта Волги',
      startMonth: 5,
      startDay: 16,
      endMonth: 6,
      endDay: 20,
      allowedGear:
          'Разрешена ловля только в пределах административных границ населённых пунктов поплавочной/донной снастью или спиннингом с берега (в рамках нормы).',
      extraNotes:
          'Отдельно действует запрет на зимовальных ямах и на воблу (проверяйте актуальный приказ на текущий год).',
      centerLat: 46.35,
      centerLon: 48.03,
    ),
    SpawningBanRegion(
      id: 'don_azov',
      name: 'Дон / Ростовская обл. и Азовский бассейн',
      waterbodies: 'Дон, Северский Донец, Цимлянское и Веселовское вдхр.',
      startMonth: 4,
      startDay: 1,
      endMonth: 5,
      endDay: 31,
      allowedGear:
          'С берега 1 удочкой (до 2 крючков) вне нерестовых участков и проток.',
      extraNotes:
          'На разных участках Дона и Цимлянского вдхр. сроки сдвигаются (до 15 июня для судака/леща).',
      centerLat: 47.23,
      centerLon: 39.70,
    ),
    SpawningBanRegion(
      id: 'ob_siberia',
      name: 'Обь-Иртышский бассейн / Сибирь',
      waterbodies: 'Обь, Иртыш, Обское море, Томь, Чулым',
      startMonth: 4,
      startDay: 20,
      endMonth: 5,
      endDay: 20,
      allowedGear:
          'С берега 1 донной или поплавочной удочкой, либо спиннингом с берега (в зависимости от субъекта — не более 2 крючков).',
      extraNotes:
          'Сроки отличаются по областям (Новосибирская: 20.04–20.05 в реке и 25.04–10.06 в вдхр.; в ХМАО/ЯНАО позже, в мае–июне).',
      centerLat: 55.01,
      centerLon: 82.93,
    ),
    SpawningBanRegion(
      id: 'nw_ladoga',
      name: 'Северо-Запад / Ладога, Нева, Свирь',
      waterbodies: 'Ладожское и Онежское озёра, Нева, Волхов, Финский залив',
      startMonth: 5,
      startDay: 1,
      endMonth: 6,
      endDay: 15,
      allowedGear:
          'В период запрета на щуку/судака/леща разрешена поплавочная удочка с берега вне нерестилищ.',
      extraNotes:
          'Для щуки запрет обычно начинается с распаления льда по 31 мая, для судака и леща — до 15 июня; запрет на моторы до 20 июня.',
      centerLat: 60.00,
      centerLon: 31.00,
    ),
  ];

  Future<SpawningBanRegion> getSelectedBanRegion({
    double? lat,
    double? lon,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_banRegionKey);
    if (savedId != null) {
      for (final r in spawningRegions) {
        if (r.id == savedId) return r;
      }
    }
    if (lat != null && lon != null) {
      return suggestNearestRegion(lat, lon);
    }
    return spawningRegions.first;
  }

  Future<void> saveSelectedBanRegion(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_banRegionKey, id);
  }

  SpawningBanRegion suggestNearestRegion(double lat, double lon) {
    var best = spawningRegions.first;
    var bestScore = double.infinity;
    for (final r in spawningRegions) {
      final dLat = r.centerLat - lat;
      final dLon = r.centerLon - lon;
      final score = dLat * dLat + dLon * dLon;
      if (score < bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  Future<WeatherForecastData> fetchForecast({
    required double lat,
    required double lon,
  }) async {
    final cacheKey =
        '$_cachePrefix${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
    final prefs = await SharedPreferences.getInstance();

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'current':
          'temperature_2m,apparent_temperature,relative_humidity_2m,pressure_msl,cloud_cover,wind_speed_10m,wind_gusts_10m,wind_direction_10m,weather_code',
      'hourly':
          'temperature_2m,pressure_msl,wind_speed_10m,wind_gusts_10m,wind_direction_10m,precipitation_probability,cloud_cover,weather_code',
      'daily': 'sunrise,sunset',
      'wind_speed_unit': 'ms',
      'past_days': '1',
      'forecast_days': '2',
      'timezone': 'auto',
    });

    final client = HttpClient();
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      await prefs.setString(
        cacheKey,
        jsonEncode({
          'fetchedAt': DateTime.now().toIso8601String(),
          'payload': json,
        }),
      );

      return _parseOpenMeteoJson(
        json: json,
        lat: lat,
        lon: lon,
        fetchedAt: DateTime.now(),
        isFromCache: false,
      );
    } catch (e) {
      final cachedRaw = prefs.getString(cacheKey);
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        final wrapper = jsonDecode(cachedRaw) as Map<String, dynamic>;
        final fetchedAt =
            DateTime.tryParse((wrapper['fetchedAt'] ?? '').toString()) ??
                DateTime.now();
        final payload = Map<String, dynamic>.from(wrapper['payload'] as Map);
        return _parseOpenMeteoJson(
          json: payload,
          lat: lat,
          lon: lon,
          fetchedAt: fetchedAt,
          isFromCache: true,
        );
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  WeatherForecastData _parseOpenMeteoJson({
    required Map<String, dynamic> json,
    required double lat,
    required double lon,
    required DateTime fetchedAt,
    required bool isFromCache,
  }) {
    final current = Map<String, dynamic>.from(json['current'] as Map);
    final hourly = Map<String, dynamic>.from(json['hourly'] as Map);
    final daily = json['daily'] != null
        ? Map<String, dynamic>.from(json['daily'] as Map)
        : <String, dynamic>{};

    final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 0.0;
    final apparent =
        (current['apparent_temperature'] as num?)?.toDouble() ?? temp;
    final humidity =
        (current['relative_humidity_2m'] as num?)?.toInt() ?? 0;
    final pressureMmHg =
        ((current['pressure_msl'] as num?)?.toDouble() ?? 1013.25) * _hpaToMmHg;
    final cloud = (current['cloud_cover'] as num?)?.toInt() ?? 0;
    final wind = (current['wind_speed_10m'] as num?)?.toDouble() ?? 0.0;
    final gusts = (current['wind_gusts_10m'] as num?)?.toDouble() ?? wind;
    final windDir = (current['wind_direction_10m'] as num?)?.toDouble() ?? 0.0;
    final weatherCode = (current['weather_code'] as num?)?.toInt() ?? 0;

    final sunriseList = (daily['sunrise'] as List<dynamic>?) ?? const [];
    final sunsetList = (daily['sunset'] as List<dynamic>?) ?? const [];
    DateTime? sunrise;
    DateTime? sunset;
    if (sunriseList.length > 1) {
      sunrise = DateTime.tryParse(sunriseList[1].toString());
    } else if (sunriseList.isNotEmpty) {
      sunrise = DateTime.tryParse(sunriseList.first.toString());
    }
    if (sunsetList.length > 1) {
      sunset = DateTime.tryParse(sunsetList[1].toString());
    } else if (sunsetList.isNotEmpty) {
      sunset = DateTime.tryParse(sunsetList.first.toString());
    }

    final times = (hourly['time'] as List<dynamic>?) ?? const [];
    final hTemps = (hourly['temperature_2m'] as List<dynamic>?) ?? const [];
    final hPress = (hourly['pressure_msl'] as List<dynamic>?) ?? const [];
    final hWind = (hourly['wind_speed_10m'] as List<dynamic>?) ?? const [];
    final hGusts = (hourly['wind_gusts_10m'] as List<dynamic>?) ?? const [];
    final hWindDir =
        (hourly['wind_direction_10m'] as List<dynamic>?) ?? const [];
    final hPrecip =
        (hourly['precipitation_probability'] as List<dynamic>?) ?? const [];
    final hCloud = (hourly['cloud_cover'] as List<dynamic>?) ?? const [];
    final hCode = (hourly['weather_code'] as List<dynamic>?) ?? const [];

    final currentTime =
        DateTime.tryParse((current['time'] ?? '').toString()) ?? DateTime.now();

    var closestNowIdx = 0;
    var bestDiffMinutes = 1 << 30;
    final parsedTimes = <DateTime>[];

    for (var i = 0; i < times.length; i++) {
      final t = DateTime.tryParse(times[i].toString()) ?? currentTime;
      parsedTimes.add(t);
      final diff = t.difference(currentTime).inMinutes.abs();
      if (diff < bestDiffMinutes) {
        bestDiffMinutes = diff;
        closestNowIdx = i;
      }
    }

    double pressureAt(int idx) {
      if (idx < 0 || idx >= hPress.length || hPress[idx] == null) {
        return pressureMmHg;
      }
      return (hPress[idx] as num).toDouble() * _hpaToMmHg;
    }

    final prev6Idx = (closestNowIdx - 6).clamp(0, hPress.length - 1);
    final delta6h = hPress.isEmpty ? 0.0 : (pressureMmHg - pressureAt(prev6Idx));

    final currentBite = _evaluateBiteIndex(
      pressureMmHg: pressureMmHg,
      pressureDelta6hMmHg: delta6h,
      windSpeedMs: wind,
      windGustsMs: gusts,
      cloudCover: cloud,
      weatherCode: weatherCode,
      time: currentTime,
      sunrise: sunrise,
      sunset: sunset,
    );

    final nextHours = <HourlyWeatherPoint>[];
    final maxIdx = (closestNowIdx + 24).clamp(0, parsedTimes.length);
    for (var i = closestNowIdx; i < maxIdx; i++) {
      final pMm = pressureAt(i);
      final pPrev = i >= 6 ? pressureAt(i - 6) : pMm;
      final w = (i < hWind.length && hWind[i] != null)
          ? (hWind[i] as num).toDouble()
          : wind;
      final g = (i < hGusts.length && hGusts[i] != null)
          ? (hGusts[i] as num).toDouble()
          : w;
      final c = (i < hCloud.length && hCloud[i] != null)
          ? (hCloud[i] as num).toInt()
          : cloud;
      final wc = (i < hCode.length && hCode[i] != null)
          ? (hCode[i] as num).toInt()
          : weatherCode;
      final t = (i < hTemps.length && hTemps[i] != null)
          ? (hTemps[i] as num).toDouble()
          : temp;
      final wd = (i < hWindDir.length && hWindDir[i] != null)
          ? (hWindDir[i] as num).toDouble()
          : windDir;
      final pp = (i < hPrecip.length && hPrecip[i] != null)
          ? (hPrecip[i] as num).toInt()
          : 0;

      final eval = _evaluateBiteIndex(
        pressureMmHg: pMm,
        pressureDelta6hMmHg: pMm - pPrev,
        windSpeedMs: w,
        windGustsMs: g,
        cloudCover: c,
        weatherCode: wc,
        time: parsedTimes[i],
        sunrise: sunrise,
        sunset: sunset,
      );

      nextHours.add(
        HourlyWeatherPoint(
          time: parsedTimes[i],
          temperatureC: t,
          pressureMmHg: pMm,
          windSpeedMs: w,
          windGustsMs: g,
          windDirectionDeg: wd,
          precipitationProb: pp,
          cloudCover: c,
          weatherCode: wc,
          biteIndex: eval.$1,
        ),
      );
    }

    return WeatherForecastData(
      latitude: lat,
      longitude: lon,
      fetchedAt: fetchedAt,
      isFromCache: isFromCache,
      temperatureC: temp,
      apparentTemperatureC: apparent,
      humidityPercent: humidity,
      pressureMmHg: pressureMmHg,
      pressureDelta6hMmHg: delta6h,
      windSpeedMs: wind,
      windGustsMs: gusts,
      windDirectionDeg: windDir,
      cloudCover: cloud,
      weatherCode: weatherCode,
      sunrise: sunrise,
      sunset: sunset,
      biteIndex: currentBite.$1,
      biteVerdict: biteVerdictLabel(currentBite.$1),
      biteFactors: currentBite.$2,
      nextHours: nextHours,
    );
  }

  (int, List<BiteFactor>) _evaluateBiteIndex({
    required double pressureMmHg,
    required double pressureDelta6hMmHg,
    required double windSpeedMs,
    required double windGustsMs,
    required int cloudCover,
    required int weatherCode,
    required DateTime time,
    DateTime? sunrise,
    DateTime? sunset,
  }) {
    // 1. Давление и его стабильность (до 35 баллов)
    final absDelta = pressureDelta6hMmHg.abs();
    int pressureScore;
    String pressureNote;
    if (absDelta <= 1.2) {
      pressureScore = 33;
      pressureNote = 'Стабильное давление (идеально для активности рыбы)';
    } else if (pressureDelta6hMmHg > 0 && absDelta <= 2.8) {
      pressureScore = 31;
      pressureNote = 'Плавный рост давления (хороший признак)';
    } else if (absDelta <= 3.0) {
      pressureScore = 24;
      pressureNote = 'Умеренное изменение давления';
    } else if (absDelta <= 5.0) {
      pressureScore = 14;
      pressureNote = 'Заметный перепад давления — клёв может капризничать';
    } else {
      pressureScore = 7;
      pressureNote = 'Резкий скачок давления за 6 ч';
    }
    if (pressureMmHg >= 748 && pressureMmHg <= 764 && pressureScore < 35) {
      pressureScore = (pressureScore + 2).clamp(0, 35);
    }

    // 2. Ветер и порывы (до 25 баллов)
    int windScore;
    String windNote;
    if (windSpeedMs >= 1.5 && windSpeedMs <= 5.0 && windGustsMs <= 8.5) {
      windScore = 24;
      windNote = 'Лёгкая рябь на воде — оптимально для маскировки и проводки';
    } else if (windSpeedMs < 1.5) {
      windScore = 17;
      windNote = 'Штиль — рыба осторожнее на мели';
    } else if (windSpeedMs <= 7.5 && windGustsMs <= 12.0) {
      windScore = 15;
      windNote = 'Умеренный ветер — учитывайте снос лодки и приманки';
    } else {
      windScore = 6;
      windNote = 'Сильный ветер / порывы — сложные условия на воде';
    }

    // 3. Облачность и осадки (до 20 баллов)
    int skyScore;
    String skyNote;
    if (weatherCode >= 95) {
      skyScore = 4;
      skyNote = 'Гроза — клёв нестабильный и опасно на воде';
    } else if (weatherCode >= 63 && weatherCode <= 82) {
      skyScore = 11;
      skyNote = 'Сильные осадки';
    } else if (cloudCover >= 40 && cloudCover <= 85) {
      skyScore = 19;
      skyNote = 'Переменная / плотная облачность — комфортно для хищника';
    } else if (cloudCover > 85) {
      skyScore = 17;
      skyNote = 'Пасмурно — рыба смелее выходит на бровки';
    } else {
      skyScore = 13;
      skyNote = 'Ясно — лучше искать рыбу на глубине или в тени';
    }

    // 4. Время суток / зорька (до 20 баллов)
    final hour = time.hour + time.minute / 60.0;
    final srHour = sunrise != null
        ? (sunrise.hour + sunrise.minute / 60.0)
        : 6.5;
    final ssHour = sunset != null
        ? (sunset.hour + sunset.minute / 60.0)
        : 18.5;

    final distToZorka = [
      (hour - srHour).abs(),
      (hour - ssHour).abs(),
    ].reduce((a, b) => a < b ? a : b);

    int timeScore;
    String timeNote;
    if (distToZorka <= 1.5) {
      timeScore = 20;
      timeNote = 'Окно зорьки — пик суточной активности';
    } else if (distToZorka <= 3.0) {
      timeScore = 15;
      timeNote = 'Хорошее утреннее/вечернее время';
    } else if (hour >= 10 && hour <= 15) {
      timeScore = 10;
      timeNote = 'Середина дня — лучше пробивать ямы и свалы';
    } else {
      timeScore = 11;
      timeNote = 'Ночное время — точечный выход (судак, сом, налим)';
    }

    final total = (pressureScore + windScore + skyScore + timeScore)
        .clamp(0, 100);

    return (
      total,
      [
        BiteFactor(
          title: 'Давление',
          detail: pressureNote,
          score: pressureScore,
          maxScore: 35,
        ),
        BiteFactor(
          title: 'Ветер',
          detail: windNote,
          score: windScore,
          maxScore: 25,
        ),
        BiteFactor(
          title: 'Небо и осадки',
          detail: skyNote,
          score: skyScore,
          maxScore: 20,
        ),
        BiteFactor(
          title: 'Время суток',
          detail: timeNote,
          score: timeScore,
          maxScore: 20,
        ),
      ],
    );
  }

  static String biteVerdictLabel(int score) {
    if (score >= 75) return 'Отличный клёв';
    if (score >= 55) return 'Хороший клёв';
    if (score >= 38) return 'Средний клёв';
    return 'Слабый клёв';
  }

  static String compassFromDegrees(double deg) {
    const dirs = ['С', 'СВ', 'В', 'ЮВ', 'Ю', 'ЮЗ', 'З', 'СЗ'];
    final idx = (((deg % 360) + 360) % 360 / 45).round() % 8;
    return dirs[idx];
  }

  static String describeWeatherCode(int code) {
    if (code == 0) return 'Ясно';
    if (code <= 2) return 'Малооблачно';
    if (code == 3) return 'Пасмурно';
    if (code == 45 || code == 48) return 'Туман';
    if (code >= 51 && code <= 57) return 'Морось';
    if (code >= 61 && code <= 67) return 'Дождь';
    if (code >= 71 && code <= 77) return 'Снег';
    if (code >= 80 && code <= 82) return 'Ливень';
    if (code >= 85 && code <= 86) return 'Снегопад';
    if (code >= 95) return 'Гроза';
    return 'Переменная погода';
  }
}
