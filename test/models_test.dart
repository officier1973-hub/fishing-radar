import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:fishing_radar/models/fishing_spot.dart';
import 'package:fishing_radar/services/api_service.dart';
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
}
