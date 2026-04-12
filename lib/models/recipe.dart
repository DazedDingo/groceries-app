import 'package:cloud_firestore/cloud_firestore.dart';

class RecipeIngredient {
  final String name;
  final int quantity;
  final String? categoryId;

  const RecipeIngredient({required this.name, required this.quantity, this.categoryId});

  Map<String, dynamic> toMap() => {
    'name': name, 'quantity': quantity, 'categoryId': categoryId,
  };

  factory RecipeIngredient.fromMap(Map<String, dynamic> m) => RecipeIngredient(
    name: m['name'] ?? '',
    quantity: m['quantity'] ?? 1,
    categoryId: m['categoryId'],
  );
}

class Recipe {
  final String id;
  final String name;
  final List<RecipeIngredient> ingredients;
  final String? notes;

  const Recipe({
    required this.id, required this.name, required this.ingredients, this.notes,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'ingredients': ingredients.map((i) => i.toMap()).toList(),
    'notes': notes,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory Recipe.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Recipe(
      id: doc.id,
      name: d['name'] ?? '',
      ingredients: (d['ingredients'] as List<dynamic>?)
          ?.map((i) => RecipeIngredient.fromMap(i as Map<String, dynamic>))
          .toList() ?? [],
      notes: d['notes'],
    );
  }
}
