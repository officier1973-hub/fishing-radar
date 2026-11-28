import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:fishing_radar/models/boat_track.dart';
import 'package:fishing_radar/models/chat_message.dart';
import 'package:fishing_radar/models/fishing_spot.dart';
import 'package:fishing_radar/services/api_service.dart';
import 'package:fishing_radar/services/gpx_service.dart';
import 'package:fishing_radar/services/weather_service.dart';

void main() {
  group('FishingSpot и Круг доверия', () {
    final baseSpot = FishingSpot(
      id: 'spot-1',
      latitude: 53.2100,
      longitude: 50.1600,
      publicLatitude: 53.2120,
      publicLongitude: 50.1620,
      depthMeters: 6.5,
      bottomType: 'Бровка / свал',
      fishSpecies: 'Судак',
      fishWeightKg: 2.4,
      isPrivateCircle: true,
      isTrustedFriend: false,
      userId: 'owner-1',
      createdAt: DateTime(2026, 11, 21, 10, 0),
    );

    test('владелец видит точную координату даже в Круге доверия', () {
      expect(
        baseSpot.displayPointFor('owner-1'),
        const LatLng(53.2100, 50.1600),
      );
    });

    test('посторонний видит смещённую координату', () {
      expect(
        baseSpot.displayPointFor('stranger-2'),
        const LatLng(53.2120, 50.1620),
      );
      expect(
        baseSpot.displayPointFor(null),
        const LatLng(53.2120, 50.1620),
      );
    });

    test('доверенный друг видит точную координату', () {
      final friendSpot = baseSpot.copyWith(isTrustedFriend: true);
      expect(
        friendSpot.displayPointFor('friend-3'),
        const LatLng(53.2100, 50.1600),
      );
    });

    test('сериализация toJson / fromJson сохраняет все поля', () {
      final friendSpot = baseSpot.copyWith(isTrustedFriend: true);
      final restored = FishingSpot.fromJson(friendSpot.toJson());
      expect(restored.id, 'spot-1');
      expect(restored.isPrivateCircle, isTrue);
      expect(restored.isTrustedFriend, isTrue);
      expect(restored.depthMeters, 6.5);
      expect(restored.fishSpecies, 'Судак');
    });
  });

  group('BoatTrack и ChatMessage', () {
    test('BoatTrack вычисляет длительность, среднюю скорость и сериализуется', () {
      final track = BoatTrack(
        id: 'trk-1',
        name: 'Проход по Волге',
        startedAt: DateTime(2026, 11, 28, 8, 0),
        endedAt: DateTime(2026, 11, 28, 9, 0),
        distanceMeters: 18000,
        maxSpeedKmh: 34.5,
        points: const [
          LatLng(53.2000, 50.1500),
          LatLng(53.2500, 50.1800),
        ],
      );

      expect(track.duration, const Duration(hours: 1));
      expect(track.avgSpeedKmh, closeTo(18.0, 0.01));

      final restored = BoatTrack.fromJson(track.toJson());
      expect(restored.id, 'trk-1');
      expect(restored.name, 'Проход по Волге');
      expect(restored.points.length, 2);
      expect(restored.points.first.latitude, closeTo(53.2, 0.0001));
    });

    test('ChatMessage.fromJson корректно читает поля', () {
      final msg = ChatMessage.fromJson({
        'id': 'm-1',
        'region': 'Волга (Самара)',
        'user_id': 'u-1',
        'author_name': 'Алексей',
        'message_text': 'Судак вышел на бровку',
        'created_at': '2026-11-28T09:15:00.000Z',
      });

      expect(msg.id, 'm-1');
      expect(msg.region, 'Волга (Самара)');
      expect(msg.authorName, 'Алексей');
      expect(msg.text, 'Судак вышел на бровку');
    });
  });

  group('TrustedPeer', () {
    test('корректно различает входящее и исходящее доверие', () {
      final outgoing = TrustedPeer.fromJson({
        'id': '1',
        'peer_user_id': 'u2',
        'peer_name': 'Иван',
        'direction': 'outgoing',
        'created_at': '2026-11-21T10:00:00.000Z',
      });
      final incoming = TrustedPeer.fromJson({
        'id': '2',
        'peer_user_id': 'u3',
        'peer_name': 'Пётр',
        'direction': 'incoming',
        'created_at': '2026-11-21T10:00:00.000Z',
      });

      expect(outgoing.isOutgoing, isTrue);
      expect(incoming.isOutgoing, isFalse);
    });
  });

  group('WeatherService и нерестовый календарь', () {
    test('компас переводит градусы в румбы', () {
      expect(WeatherService.compassFromDegrees(0), 'С');
      expect(WeatherService.compassFromDegrees(90), 'В');
      expect(WeatherService.compassFromDegrees(180), 'Ю');
      expect(WeatherService.compassFromDegrees(270), 'З');
    });

    test('оценка индекса клёва возвращает корректные статусы', () {
      expect(WeatherService.biteVerdictLabel(82), 'Отличный клёв');
      expect(WeatherService.biteVerdictLabel(62), 'Хороший клёв');
      expect(WeatherService.biteVerdictLabel(42), 'Средний клёв');
      expect(WeatherService.biteVerdictLabel(20), 'Слабый клёв');
    });

    test('проверка дат нерестового запрета', () {
      final samara = WeatherService.spawningRegions.firstWhere(
        (r) => r.id == 'samara_volga',
      );
      expect(samara.periodLabel, '20.04 – 10.06');
      expect(samara.isBanActiveOn(DateTime(2026, 5, 10)), isTrue);
      expect(samara.isBanActiveOn(DateTime(2026, 7, 15)), isFalse);
    });

    test('подбирает ближайший рыбохозяйственный регион по координатам', () {
      final service = WeatherService();
      expect(service.suggestNearestRegion(53.20, 50.15).id, 'samara_volga');
      expect(service.suggestNearestRegion(55.75, 37.62).id, 'moscow_oka');
    });
  });

  group('GpxService (экспорт и импорт GPX)', () {
    final gpxService = GpxService();

    test('sanitizeFileName очищает спецсимволы и добавляет .gpx', () {
      expect(
        GpxService.sanitizeFileName('Выезд 28/11: Волжский*'),
        'Выезд_28_11_Волжский.gpx',
      );
      expect(
        GpxService.sanitizeFileName('track.gpx'),
        'track.gpx',
      );
    });

    test('полный цикл экспорта и импорта точек и треков с сохранением метаданных', () {
      final spot = FishingSpot(
        id: 's-1',
        latitude: 53.2100,
        longitude: 50.1600,
        depthMeters: 7.5,
        bottomType: 'Коряжник & камни',
        fishSpecies: 'Судак',
        fishWeightKg: 3.1,
        comment: 'Джиг <18 г> "поролон"',
        userId: 'me',
        createdAt: DateTime.utc(2026, 11, 28, 7, 30),
      );
      final track = BoatTrack(
        id: 't-1',
        name: 'Свал <утро>',
        startedAt: DateTime.utc(2026, 11, 28, 7, 0),
        endedAt: DateTime.utc(2026, 11, 28, 7, 20),
        distanceMeters: 2500,
        maxSpeedKmh: 16.0,
        points: const [
          LatLng(53.2000, 50.1500),
          LatLng(53.2100, 50.1600),
        ],
      );

      final xml = gpxService.buildGpx(
        tracks: [track],
        spots: [spot],
        currentUserId: 'me',
      );
      final parsed = gpxService.parseGpx(xml);

      expect(parsed.spots.length, 1);
      final pSpot = parsed.spots.first;
      expect(pSpot.latitude, closeTo(53.2100, 0.00001));
      expect(pSpot.longitude, closeTo(50.1600, 0.00001));
      expect(pSpot.depthMeters, closeTo(7.5, 0.01));
      expect(pSpot.bottomType, 'Коряжник & камни');
      expect(pSpot.fishSpecies, 'Судак');
      expect(pSpot.fishWeightKg, closeTo(3.1, 0.01));
      expect(pSpot.comment, 'Джиг <18 г> "поролон"');

      expect(parsed.tracks.length, 1);
      final pTrack = parsed.tracks.first;
      expect(pTrack.name, 'Свал <утро>');
      expect(pTrack.points.length, 2);
      expect(pTrack.distanceMeters, greaterThan(1000));
    });

    test('при экспорте чужой секретной точки выгружает смещённые координаты', () {
      final strangerPrivateSpot = FishingSpot(
        id: 's-priv',
        latitude: 53.2100,
        longitude: 50.1600,
        publicLatitude: 53.2125,
        publicLongitude: 50.1625,
        depthMeters: 5.0,
        bottomType: 'Бровка',
        fishSpecies: 'Щука',
        isPrivateCircle: true,
        isTrustedFriend: false,
        userId: 'other-user',
        createdAt: DateTime.utc(2026, 11, 28, 8, 0),
      );

      final xml = gpxService.buildGpx(
        spots: [strangerPrivateSpot],
        currentUserId: 'my-user',
      );
      final parsed = gpxService.parseGpx(xml);
      expect(parsed.spots.single.latitude, closeTo(53.2125, 0.00001));
      expect(parsed.spots.single.longitude, closeTo(50.1625, 0.00001));
    });

    test('разбирает сторонний GPX с CDATA, маршрутом <rte> и самозакрывающимися тегами', () {
      const externalGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <wpt lon="50.1800" lat="53.2200">
    <name><![CDATA[Коряга глубина 6.4 м]]></name>
    <desc>Свал с 4 на 6.4 м, берш</desc>
    <type>Берш</type>
  </wpt>
  <rte>
    <name>Подход к косе</name>
    <rtept lat="53.2000" lon="50.1500" />
    <rtept lat="53.2050" lon="50.1550"/>
  </rte>
</gpx>
''';

      final parsed = gpxService.parseGpx(externalGpx);
      expect(parsed.spots.length, 1);
      expect(parsed.spots.first.fishSpecies, 'Берш');
      expect(parsed.spots.first.depthMeters, closeTo(6.4, 0.01));
      expect(parsed.tracks.length, 1);
      expect(parsed.tracks.first.name, 'Подход к косе');
      expect(parsed.tracks.first.points.length, 2);
    });
  });
}
