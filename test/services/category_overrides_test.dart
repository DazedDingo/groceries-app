import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/category.dart';
import 'package:groceries_app/services/category_guesser.dart';
import 'package:groceries_app/services/category_overrides.dart';

void main() {
  group('CategoryOverrideService + guessCategory', () {
    late FakeFirebaseFirestore fakeDb;
    late CategoryOverrideService service;

    final categories = <GroceryCategory>[
      const GroceryCategory(id: 'dairy', name: 'Dairy', color: Colors.white, addedBy: 'seed'),
      const GroceryCategory(id: 'produce', name: 'Produce', color: Colors.green, addedBy: 'seed'),
      const GroceryCategory(id: 'snacks', name: 'Snacks', color: Colors.orange, addedBy: 'seed'),
    ];

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = CategoryOverrideService(db: fakeDb);
    });

    test('saved override is keyed by lowercased name', () async {
      await service.saveOverride(
        householdId: 'hh1',
        itemName: '  Cheddar  ',
        categoryId: 'snacks',
      );

      final snap = await fakeDb.collection('households/hh1/categoryOverrides').get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.id, 'cheddar');
      expect(snap.docs.first['categoryId'], 'snacks');
    });

    test('override takes precedence over keyword match in guessCategory', () async {
      // Without an override, "cheddar" matches the dairy keyword.
      expect(guessCategory('Cheddar', categories)?.id, 'dairy');

      // After the user reassigns it, the override should win.
      await service.saveOverride(
        householdId: 'hh1',
        itemName: 'Cheddar',
        categoryId: 'snacks',
      );
      final overrides = await service.overridesStream('hh1').first;

      expect(guessCategory('Cheddar', categories, overrides)?.id, 'snacks');
      // Case insensitivity: same key still resolves regardless of input casing.
      expect(guessCategory('CHEDDAR', categories, overrides)?.id, 'snacks');
    });

    test('falls back to keyword match when no override exists for the name', () async {
      await service.saveOverride(
        householdId: 'hh1',
        itemName: 'Cheddar',
        categoryId: 'snacks',
      );
      final overrides = await service.overridesStream('hh1').first;

      // Different item — no override entry, so the keyword path runs.
      expect(guessCategory('Apple', categories, overrides)?.id, 'produce');
    });

    test('clearOverride removes the stored mapping so guesser takes over again', () async {
      await service.saveOverride(
        householdId: 'hh1',
        itemName: 'Cheddar',
        categoryId: 'snacks',
      );
      var overrides = await service.overridesStream('hh1').first;
      expect(guessCategory('Cheddar', categories, overrides)?.id, 'snacks');

      await service.clearOverride(householdId: 'hh1', itemName: 'Cheddar');

      final snap = await fakeDb.collection('households/hh1/categoryOverrides').get();
      expect(snap.docs, isEmpty);

      overrides = await service.overridesStream('hh1').first;
      // Keyword guesser is back in charge.
      expect(guessCategory('Cheddar', categories, overrides)?.id, 'dairy');
    });

    test('clearOverride is case-insensitive and ignores blank input', () async {
      await service.saveOverride(
        householdId: 'hh1',
        itemName: 'Cheddar',
        categoryId: 'snacks',
      );
      await service.clearOverride(householdId: 'hh1', itemName: '  CHEDDAR ');
      final snap = await fakeDb.collection('households/hh1/categoryOverrides').get();
      expect(snap.docs, isEmpty);

      // Blank input should no-op rather than throw.
      await service.clearOverride(householdId: 'hh1', itemName: '   ');
    });
  });
}
