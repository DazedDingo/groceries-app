import 'package:cloud_firestore/cloud_firestore.dart';

class RecipeIngredient {
  final String name;
  final int quantity;
  final String? unit;
  final String? categoryId;

  const RecipeIngredient({required this.name, required this.quantity, this.unit, this.categoryId});

  Map<String, dynamic> toMap() => {
    'name': name, 'quantity': quantity, 'unit': unit, 'categoryId': categoryId,
  };

  factory RecipeIngredient.fromMap(Map<String, dynamic> m) => RecipeIngredient(
    name: m['name'] ?? '',
    quantity: m['quantity'] ?? 1,
    unit: m['unit'],
    categoryId: m['categoryId'],
  );
}

class Recipe {
  final String id;
  final String name;
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final String? notes;
  final String? sourceUrl;
  final List<String> tags;

  const Recipe({
    required this.id, required this.name, required this.ingredients,
    this.instructions = const [], this.notes, this.sourceUrl,
    this.tags = const [],
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'ingredients': ingredients.map((i) => i.toMap()).toList(),
    'instructions': instructions,
    'notes': notes,
    'sourceUrl': sourceUrl,
    'tags': tags,
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
      instructions: (d['instructions'] as List<dynamic>?)
          ?.map((s) => s.toString())
          .toList() ?? [],
      notes: d['notes'],
      sourceUrl: d['sourceUrl'],
      tags: List<String>.from(d['tags'] ?? []),
    );
  }
}
