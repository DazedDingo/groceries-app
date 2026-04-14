import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-user 1–5 star ratings on recipes, stored at
/// `households/{hh}/recipes/{recipeId}/ratings/{uid}`.
/// Each user gets exactly one rating per recipe (keyed by uid), so writes
/// are idempotent and re-rating just overwrites.
class RecipeRatingService {
  final FirebaseFirestore _db;
  RecipeRatingService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference _ref(String householdId, String recipeId) =>
      _db.collection('households/$householdId/recipes/$recipeId/ratings');

  Future<void> setRating({
    required String householdId,
    required String recipeId,
    required String uid,
    required int rating,
  }) async {
    final clamped = rating.clamp(1, 5);
    await _ref(householdId, recipeId).doc(uid).set({
      'rating': clamped,
      'ratedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearRating({
    required String householdId,
    required String recipeId,
    required String uid,
  }) async {
    await _ref(householdId, recipeId).doc(uid).delete();
  }

  /// Stream of ratings for one recipe as a `uid → rating` map. Empty map when
  /// nobody in the household has rated yet.
  Stream<Map<String, int>> ratingsStream(String householdId, String recipeId) {
    return _ref(householdId, recipeId).snapshots().map((snap) {
      final out = <String, int>{};
      for (final d in snap.docs) {
        final r = d['rating'];
        if (r is int) out[d.id] = r;
      }
      return out;
    });
  }
}

/// Aggregate of a recipe's household ratings — used by the list/detail UI.
class RecipeRatingSummary {
  final double average;
  final int count;
  const RecipeRatingSummary({required this.average, required this.count});

  static const empty = RecipeRatingSummary(average: 0, count: 0);

  factory RecipeRatingSummary.from(Map<String, int> ratings) {
    if (ratings.isEmpty) return empty;
    final sum = ratings.values.fold<int>(0, (a, b) => a + b);
    return RecipeRatingSummary(
      average: sum / ratings.length,
      count: ratings.length,
    );
  }
}
