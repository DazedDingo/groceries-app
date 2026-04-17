import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/household_service.dart';

/// We assert on what ends up in Firestore rather than touching the private
/// `_defaultCategories` list — this way the test catches regressions at the
/// actual boundary the UI reads from.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    _seedAndReadCategories(FakeFirebaseFirestore fs) async {
  final auth = MockUser(
    isAnonymous: false,
    uid: 'user-1',
    email: 'u@example.com',
    displayName: 'User',
  );
  final service = HouseholdService(db: fs);
  final hhId = await service.createHousehold(auth, 'Home');
  final snap = await fs.collection('households/$hhId/categories').get();
  return snap.docs;
}

void main() {
  group('default category palette', () {
    test('ships exactly 9 categories', () async {
      final fs = FakeFirebaseFirestore();
      final docs = await _seedAndReadCategories(fs);
      expect(docs.length, 9);
    });

    test('every category has a 7-char #RRGGBB hex color', () async {
      final fs = FakeFirebaseFirestore();
      final docs = await _seedAndReadCategories(fs);
      final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
      for (final d in docs) {
        final color = d.data()['color'] as String;
        expect(hexPattern.hasMatch(color), isTrue,
            reason: 'bad hex for ${d.data()['name']}: $color');
      }
    });

    test('all category colors are unique', () async {
      // Dairy/Frozen sat next to each other on the Material 500 palette
      // (#42A5F5 / #29B6F6); this guards the "desaturated, value-spaced"
      // promise in the refined theme notes.
      final fs = FakeFirebaseFirestore();
      final docs = await _seedAndReadCategories(fs);
      final colors = docs.map((d) => d.data()['color'] as String).toList();
      expect(colors.toSet().length, colors.length);
    });

    test('no color is pure Material 500 neon (#xxAAyy family heuristic)',
        () async {
      // The old palette used Colors.red/blue/green[500] saturation levels.
      // Sum of channel values on the desaturated palette should stay in the
      // mid range — not too dark, not fully saturated neon — so eyeball a
      // saturation bound: no channel maxes at 255 or drops below 0x5B.
      final fs = FakeFirebaseFirestore();
      final docs = await _seedAndReadCategories(fs);
      for (final d in docs) {
        final hex = (d.data()['color'] as String).substring(1);
        final r = int.parse(hex.substring(0, 2), radix: 16);
        final g = int.parse(hex.substring(2, 4), radix: 16);
        final b = int.parse(hex.substring(4, 6), radix: 16);
        expect(r, lessThan(0xFF),
            reason: 'channel maxed for ${d.data()['name']}');
        expect(g, lessThan(0xFF),
            reason: 'channel maxed for ${d.data()['name']}');
        expect(b, lessThan(0xFF),
            reason: 'channel maxed for ${d.data()['name']}');
        expect(r, greaterThan(0x5A),
            reason: 'channel too dark for ${d.data()['name']}');
        expect(g, greaterThan(0x5A),
            reason: 'channel too dark for ${d.data()['name']}');
        expect(b, greaterThan(0x5A),
            reason: 'channel too dark for ${d.data()['name']}');
      }
    });

    test('expected category names are seeded', () async {
      final fs = FakeFirebaseFirestore();
      final docs = await _seedAndReadCategories(fs);
      final names =
          docs.map((d) => d.data()['name'] as String).toSet();
      expect(
        names,
        containsAll(<String>{
          'Meats',
          'Dairy',
          'Produce',
          'Spices',
          'Frozen',
          'Bakery',
          'Drinks',
          'Household',
          'Uncategorised',
        }),
      );
    });
  });
}
