import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/location_service.dart';

void main() {
  group('LocationService', () {
    late FakeFirebaseFirestore fakeDb;
    late LocationService service;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = LocationService(db: fakeDb);
    });

    test('customLocationsStream returns empty list when no doc exists', () async {
      final labels = await service.customLocationsStream('hh1').first;
      expect(labels, isEmpty);
    });

    test('addLocation adds a label and stream emits it', () async {
      await service.addLocation('hh1', 'Garage');
      final labels = await service.customLocationsStream('hh1').first;
      expect(labels, contains('Garage'));
    });

    test('addLocation accumulates multiple labels', () async {
      await service.addLocation('hh1', 'Garage');
      await service.addLocation('hh1', 'Spice rack');
      final labels = await service.customLocationsStream('hh1').first;
      expect(labels, containsAll(['Garage', 'Spice rack']));
    });

    test('removeLocation removes the label', () async {
      await service.addLocation('hh1', 'Garage');
      await service.addLocation('hh1', 'Spice rack');
      await service.removeLocation('hh1', 'Garage');
      final labels = await service.customLocationsStream('hh1').first;
      expect(labels, isNot(contains('Garage')));
      expect(labels, contains('Spice rack'));
    });

    test('different households are isolated', () async {
      await service.addLocation('hh1', 'Garage');
      final labelsHh2 = await service.customLocationsStream('hh2').first;
      expect(labelsHh2, isEmpty);
    });
  });
}
