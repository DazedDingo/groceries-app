import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/recipe_rating_service.dart';

void main() {
  group('RecipeRatingService', () {
    late FakeFirebaseFirestore db;
    late RecipeRatingService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = RecipeRatingService(db: db);
    });

    test('setRating writes one doc per uid (re-rating overwrites)', () async {
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'alice', rating: 4);
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'alice', rating: 5);

      final snap = await db
          .collection('households/hh1/recipes/r1/ratings')
          .get();
      expect(snap.docs.length, 1, reason: 'same uid must not duplicate');
      expect(snap.docs.first.id, 'alice');
      expect(snap.docs.first['rating'], 5);
    });

    test('setRating clamps to 1..5', () async {
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'alice', rating: 99);
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'bob', rating: -3);

      final snap = await db
          .collection('households/hh1/recipes/r1/ratings')
          .get();
      final byId = {for (final d in snap.docs) d.id: d['rating']};
      expect(byId['alice'], 5);
      expect(byId['bob'], 1);
    });

    test('clearRating removes the user\'s entry only', () async {
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'alice', rating: 4);
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'bob', rating: 2);

      await service.clearRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'alice');

      final snap = await db
          .collection('households/hh1/recipes/r1/ratings')
          .get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.id, 'bob');
    });

    test('ratingsStream surfaces all household ratings as uid → score', () async {
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'alice', rating: 5);
      await service.setRating(
          householdId: 'hh1', recipeId: 'r1', uid: 'bob', rating: 3);

      final ratings = await service.ratingsStream('hh1', 'r1').first;
      expect(ratings, {'alice': 5, 'bob': 3});
    });
  });

  group('RecipeRatingSummary', () {
    test('empty map → 0/0', () {
      final s = RecipeRatingSummary.from(const {});
      expect(s.average, 0);
      expect(s.count, 0);
    });

    test('averages multiple ratings', () {
      final s = RecipeRatingSummary.from({'a': 5, 'b': 3, 'c': 4});
      expect(s.count, 3);
      expect(s.average, closeTo(4.0, 0.001));
    });
  });
}
