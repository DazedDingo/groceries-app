import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/recipe.dart';

class RecipesService {
  final FirebaseFirestore _db;
  RecipesService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<Recipe>> recipesStream(String householdId) {
    return _db
        .collection('households/$householdId/recipes')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Recipe.fromFirestore).toList());
  }

  Future<String> addRecipe({
    required String householdId,
    required String name,
    required List<RecipeIngredient> ingredients,
    List<String> instructions = const [],
    String? notes,
    String? sourceUrl,
    List<String> tags = const [],
    String? addedByUid,
    String? addedByDisplayName,
  }) async {
    final ref = await _db.collection('households/$householdId/recipes').add({
      'name': name,
      'ingredients': ingredients.map((i) => i.toMap()).toList(),
      'instructions': instructions,
      'notes': notes,
      'sourceUrl': sourceUrl,
      'tags': tags,
      'addedByUid': addedByUid,
      'addedByDisplayName': addedByDisplayName,
      'addedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateRecipe({
    required String householdId,
    required String recipeId,
    required String name,
    required List<RecipeIngredient> ingredients,
    List<String> instructions = const [],
    String? notes,
    String? sourceUrl,
    List<String> tags = const [],
  }) async {
    await _db.doc('households/$householdId/recipes/$recipeId').update({
      'name': name,
      'ingredients': ingredients.map((i) => i.toMap()).toList(),
      'instructions': instructions,
      'notes': notes,
      'sourceUrl': sourceUrl,
      'tags': tags,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteRecipe({
    required String householdId,
    required String recipeId,
  }) async {
    await _db.doc('households/$householdId/recipes/$recipeId').delete();
  }

  Future<void> deleteRecipes({
    required String householdId,
    required List<String> recipeIds,
  }) async {
    if (recipeIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in recipeIds) {
      batch.delete(_db.doc('households/$householdId/recipes/$id'));
    }
    await batch.commit();
  }
}
