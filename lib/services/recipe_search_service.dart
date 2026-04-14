import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';
import 'recipe_import_service.dart';
import 'text_item_parser.dart';

enum RecipeSource { mealdb, spoonacular }

class RecipeSearchResult {
  final String id;
  final String title;
  final String? thumbUrl;
  final RecipeSource source;

  const RecipeSearchResult({
    required this.id,
    required this.title,
    this.thumbUrl,
    required this.source,
  });
}

/// Searches public recipe aggregators and returns normalised [ImportedRecipe]s.
/// TheMealDB needs no key. Spoonacular requires the caller to pass an API key.
class RecipeSearchService {
  final http.Client _client;
  RecipeSearchService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<RecipeSearchResult>> searchMealDb(String query) async {
    if (query.trim().isEmpty) return const [];
    final uri = Uri.parse(
        'https://www.themealdb.com/api/json/v1/1/search.php?s=${Uri.encodeQueryComponent(query)}');
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('TheMealDB error (${resp.statusCode})');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final meals = data['meals'];
    if (meals is! List) return const [];
    return meals
        .whereType<Map<String, dynamic>>()
        .map((m) => RecipeSearchResult(
              id: (m['idMeal'] ?? '').toString(),
              title: (m['strMeal'] ?? 'Untitled').toString(),
              thumbUrl: (m['strMealThumb'] as String?)?.trim().isNotEmpty == true
                  ? m['strMealThumb'] as String
                  : null,
              source: RecipeSource.mealdb,
            ))
        .toList();
  }

  /// TheMealDB's search endpoint already returns full recipe data, so we can
  /// fetch details from the same payload if we keep it around. For simplicity
  /// this re-queries by id via lookup.php — a single cheap round trip.
  Future<ImportedRecipe> fetchMealDb(String id) async {
    final uri = Uri.parse(
        'https://www.themealdb.com/api/json/v1/1/lookup.php?i=${Uri.encodeQueryComponent(id)}');
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('TheMealDB error (${resp.statusCode})');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final meals = data['meals'];
    if (meals is! List || meals.isEmpty) {
      throw Exception('Recipe not found');
    }
    return _mealDbToImported(meals.first as Map<String, dynamic>);
  }

  ImportedRecipe _mealDbToImported(Map<String, dynamic> m) {
    final ingredients = <RecipeIngredient>[];
    for (var i = 1; i <= 20; i++) {
      final name = (m['strIngredient$i'] ?? '').toString().trim();
      final measure = (m['strMeasure$i'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      // Parse the measure column (e.g. "200g", "1 tbsp") for quantity+unit.
      final parsed = parseTextLine('$measure $name'.trim());
      ingredients.add(RecipeIngredient(
        name: name,
        quantity: parsed.quantity,
        unit: parsed.unit,
      ));
    }

    final rawInstructions = (m['strInstructions'] ?? '').toString();
    final instructions = rawInstructions
        .split(RegExp(r'\r?\n|\.(?=\s|$)'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final tags = ((m['strTags'] as String?) ?? '')
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    return ImportedRecipe(
      name: (m['strMeal'] ?? 'Untitled').toString(),
      ingredients: ingredients,
      instructions: instructions,
      notes: [
        if ((m['strCategory'] as String?)?.isNotEmpty == true) m['strCategory'],
        if ((m['strArea'] as String?)?.isNotEmpty == true) m['strArea'],
        if (tags.isNotEmpty) 'Tags: ${tags.join(', ')}',
      ].join(' · ').trim().isEmpty
          ? null
          : [
              if ((m['strCategory'] as String?)?.isNotEmpty == true) m['strCategory'],
              if ((m['strArea'] as String?)?.isNotEmpty == true) m['strArea'],
            ].join(' · '),
      sourceUrl: (m['strSource'] as String?)?.trim().isNotEmpty == true
          ? m['strSource'] as String
          : null,
    );
  }

  Future<List<RecipeSearchResult>> searchSpoonacular(
      String query, String apiKey) async {
    if (query.trim().isEmpty) return const [];
    if (apiKey.isEmpty) throw Exception('Spoonacular API key not set');
    final uri = Uri.parse(
        'https://api.spoonacular.com/recipes/complexSearch?apiKey=${Uri.encodeQueryComponent(apiKey)}&query=${Uri.encodeQueryComponent(query)}&number=20');
    final resp = await _client.get(uri);
    if (resp.statusCode == 401 || resp.statusCode == 402) {
      throw Exception('Spoonacular: invalid key or quota exceeded');
    }
    if (resp.statusCode != 200) {
      throw Exception('Spoonacular error (${resp.statusCode})');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map((r) => RecipeSearchResult(
              id: (r['id'] ?? '').toString(),
              title: (r['title'] ?? 'Untitled').toString(),
              thumbUrl: r['image'] as String?,
              source: RecipeSource.spoonacular,
            ))
        .toList();
  }

  Future<ImportedRecipe> fetchSpoonacular(String id, String apiKey) async {
    if (apiKey.isEmpty) throw Exception('Spoonacular API key not set');
    final uri = Uri.parse(
        'https://api.spoonacular.com/recipes/${Uri.encodeQueryComponent(id)}/information?apiKey=${Uri.encodeQueryComponent(apiKey)}&includeNutrition=false');
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Spoonacular error (${resp.statusCode})');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return _spoonacularToImported(data);
  }

  ImportedRecipe _spoonacularToImported(Map<String, dynamic> d) {
    final rawIngs = (d['extendedIngredients'] as List<dynamic>?) ?? const [];
    final ingredients = <RecipeIngredient>[];
    for (final raw in rawIngs) {
      if (raw is! Map<String, dynamic>) continue;
      final name = (raw['name'] ?? raw['originalName'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final amount = raw['amount'];
      final qty = amount is num ? amount.round().clamp(1, 999) : 1;
      final unit = (raw['unit'] as String?)?.trim();
      ingredients.add(RecipeIngredient(
        name: name,
        quantity: qty,
        unit: (unit?.isNotEmpty ?? false) ? unit : null,
      ));
    }

    final analyzed = (d['analyzedInstructions'] as List<dynamic>?) ?? const [];
    final instructions = <String>[];
    for (final section in analyzed) {
      if (section is! Map<String, dynamic>) continue;
      final steps = section['steps'];
      if (steps is! List) continue;
      for (final step in steps) {
        if (step is Map<String, dynamic>) {
          final text = (step['step'] ?? '').toString().trim();
          if (text.isNotEmpty) instructions.add(text);
        }
      }
    }
    // Fallback: if analyzedInstructions empty but `instructions` plain string exists.
    if (instructions.isEmpty && d['instructions'] is String) {
      final plain = (d['instructions'] as String)
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .split(RegExp(r'\r?\n|\.(?=\s|$)'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      instructions.addAll(plain);
    }

    return ImportedRecipe(
      name: (d['title'] ?? 'Untitled').toString(),
      ingredients: ingredients,
      instructions: instructions,
      notes: (d['summary'] as String?)
          ?.replaceAll(RegExp(r'<[^>]*>'), '')
          .trim(),
      sourceUrl: (d['sourceUrl'] as String?)?.trim().isNotEmpty == true
          ? d['sourceUrl'] as String
          : null,
    );
  }
}
