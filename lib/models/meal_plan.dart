import 'package:cloud_firestore/cloud_firestore.dart';

class MealPlanEntry {
  final String id;
  final DateTime date;
  final String meal; // 'breakfast', 'lunch', 'dinner'
  final String recipeId;
  final String recipeName;
  final int servings;

  const MealPlanEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.recipeId,
    required this.recipeName,
    this.servings = 1,
  });

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'meal': meal,
    'recipeId': recipeId,
    'recipeName': recipeName,
    'servings': servings,
  };

  factory MealPlanEntry.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MealPlanEntry(
      id: doc.id,
      date: (d['date'] as Timestamp).toDate(),
      meal: d['meal'] ?? 'dinner',
      recipeId: d['recipeId'] ?? '',
      recipeName: d['recipeName'] ?? '',
      servings: d['servings'] ?? 1,
    );
  }
}
