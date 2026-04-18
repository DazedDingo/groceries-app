import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/providers/categories_provider.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/providers/pantry_provider.dart';
import 'package:groceries_app/screens/pantry/pantry_item_detail_screen.dart';
import 'package:groceries_app/services/categories_service.dart';
import 'package:groceries_app/services/category_overrides.dart';
import 'package:groceries_app/services/location_service.dart';
import 'package:groceries_app/services/pantry_service.dart';

Future<void> _seed(FakeFirebaseFirestore db) async {
  await db.doc('households/hh1/pantry/p1').set({
    'name': 'Cheddar',
    'categoryId': 'dairy',
    'preferredStores': <String>[],
    'optimalQuantity': 1,
    'currentQuantity': 1,
    'restockAfterDays': null,
    'shelfLifeDays': 30,
    'isHighPriority': false,
  });
  await db.collection('households/hh1/categories').doc('dairy').set({
    'name': 'Dairy',
    'color': '#ffffff',
    'addedBy': 'seed',
  });
  await db.collection('households/hh1/categories').doc('snacks').set({
    'name': 'Snacks',
    'color': '#ff9800',
    'addedBy': 'seed',
  });
}

Widget _wrap(FakeFirebaseFirestore db) {
  return ProviderScope(
    overrides: [
      householdIdProvider.overrideWith((ref) async => 'hh1'),
      pantryServiceProvider.overrideWithValue(PantryService(db: db)),
      categoriesServiceProvider.overrideWithValue(CategoriesService(db: db)),
      categoryOverrideServiceProvider
          .overrideWithValue(CategoryOverrideService(db: db)),
      locationServiceProvider.overrideWithValue(LocationService(db: db)),
    ],
    child: const MaterialApp(
      home: PantryItemDetailScreen(itemId: 'p1'),
    ),
  );
}

void main() {
  testWidgets('changing category updates pantry doc and writes override',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await _seed(db);

    await tester.pumpWidget(_wrap(db));
    // Let streams resolve.
    await tester.pumpAndSettle();

    // Scroll the Category card into view and open the dropdown.
    await tester.ensureVisible(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dairy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snacks').last);
    await tester.pumpAndSettle();

    // Pantry doc updated.
    final pantrySnap = await db.doc('households/hh1/pantry/p1').get();
    expect(pantrySnap.data()?['categoryId'], 'snacks');

    // Override written so the guesser learns.
    final overrideSnap =
        await db.doc('households/hh1/categoryOverrides/cheddar').get();
    expect(overrideSnap.exists, true);
    expect(overrideSnap.data()?['categoryId'], 'snacks');
  });

  testWidgets('picking the same category is a no-op (no override written)',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await _seed(db);

    await tester.pumpWidget(_wrap(db));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dairy').last);
    await tester.pumpAndSettle();
    // Tap the same value in the menu.
    await tester.tap(find.text('Dairy').last);
    await tester.pumpAndSettle();

    final overrideSnap =
        await db.doc('households/hh1/categoryOverrides/cheddar').get();
    expect(overrideSnap.exists, false);
  });
}
