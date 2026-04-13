import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meal_plan.dart';

class MealPlanService {
  final FirebaseFirestore _db;
  MealPlanService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference _ref(String householdId) =>
      _db.collection('households/$householdId/mealPlan');

  Stream<List<MealPlanEntry>> weekStream(String householdId, DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return _ref(householdId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .where('date', isLessThan: Timestamp.fromDate(weekEnd))
        .snapshots()
        .map((snap) => snap.docs.map(MealPlanEntry.fromFirestore).toList()
          ..sort((a, b) {
            final cmp = a.date.compareTo(b.date);
            if (cmp != 0) return cmp;
            return _mealOrder(a.meal).compareTo(_mealOrder(b.meal));
          }));
  }

  Future<void> addEntry({
    required String householdId,
    required DateTime date,
    required String meal,
    required String recipeId,
    required String recipeName,
    int servings = 1,
  }) async {
    await _ref(householdId).add(MealPlanEntry(
      id: '',
      date: DateTime(date.year, date.month, date.day),
      meal: meal,
      recipeId: recipeId,
      recipeName: recipeName,
      servings: servings,
    ).toMap());
  }

  Future<void> removeEntry(String householdId, String entryId) =>
      _ref(householdId).doc(entryId).delete();

  static int _mealOrder(String meal) => switch (meal) {
    'breakfast' => 0,
    'lunch' => 1,
    'dinner' => 2,
    _ => 3,
  };
}
