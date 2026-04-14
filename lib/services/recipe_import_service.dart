import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';
import 'text_item_parser.dart';

class ImportedRecipe {
  final String name;
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final String? notes;
  final String? sourceUrl;

  const ImportedRecipe({
    required this.name,
    required this.ingredients,
    this.instructions = const [],
    this.notes,
    this.sourceUrl,
  });
}

/// Fetches a URL and attempts to extract a recipe from JSON-LD (schema.org Recipe)
/// or falls back to OpenGraph / title + manual ingredient entry.
class RecipeImportService {
  final http.Client _client;
  RecipeImportService({http.Client? client}) : _client = client ?? http.Client();

  Future<ImportedRecipe> importFromUrl(String url) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {'User-Agent': 'GroceriesApp/1.0'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch page (${response.statusCode})');
    }

    final html = response.body;

    // Try JSON-LD first (most recipe sites use this)
    final recipe = _tryJsonLd(html, url);
    if (recipe != null) return recipe;

    // Fallback: extract title and return empty ingredients for manual entry
    final title = _extractTitle(html);
    return ImportedRecipe(
      name: title ?? 'Imported Recipe',
      ingredients: [],
      notes: 'Imported from: $url',
      sourceUrl: url,
    );
  }

  ImportedRecipe? _tryJsonLd(String html, String sourceUrl) {
    // Find all <script type="application/ld+json"> blocks
    final pattern = RegExp(
      r'<script[^>]*type\s*=\s*"application/ld\+json"[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(html)) {
      final jsonStr = match.group(1)?.trim();
      if (jsonStr == null || jsonStr.isEmpty) continue;

      try {
        final decoded = json.decode(jsonStr);
        final recipe = _findRecipeInJson(decoded, sourceUrl);
        if (recipe != null) return recipe;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  ImportedRecipe? _findRecipeInJson(dynamic data, String sourceUrl) {
    if (data is List) {
      for (final item in data) {
        final result = _findRecipeInJson(item, sourceUrl);
        if (result != null) return result;
      }
      return null;
    }

    if (data is! Map<String, dynamic>) return null;

    // Check @graph pattern
    if (data.containsKey('@graph')) {
      return _findRecipeInJson(data['@graph'], sourceUrl);
    }

    final type = data['@type'];
    final isRecipe = type == 'Recipe' ||
        (type is List && type.contains('Recipe'));

    if (!isRecipe) return null;

    final name = data['name'] as String? ?? 'Imported Recipe';
    final description = data['description'] as String?;
    final rawIngredients = data['recipeIngredient'] as List<dynamic>? ?? [];
    final rawInstructions = data['recipeInstructions'];

    final ingredients = rawIngredients
        .map((raw) => _parseIngredientString(raw.toString()))
        .toList();

    final instructions = _parseInstructions(rawInstructions);

    return ImportedRecipe(
      name: name,
      ingredients: ingredients,
      instructions: instructions,
      notes: description,
      sourceUrl: sourceUrl,
    );
  }

  /// Parse recipeInstructions which can be a list of strings, a list of
  /// HowToStep objects, or a list of HowToSection objects.
  List<String> _parseInstructions(dynamic data) {
    if (data == null) return [];
    if (data is String) return [data];
    if (data is! List) return [];

    final steps = <String>[];
    for (final item in data) {
      if (item is String) {
        final cleaned = _stripHtml(item).trim();
        if (cleaned.isNotEmpty) steps.add(cleaned);
      } else if (item is Map<String, dynamic>) {
        final type = item['@type']?.toString() ?? '';
        if (type == 'HowToStep') {
          final text = (item['text'] ?? item['name'] ?? '').toString();
          final cleaned = _stripHtml(text).trim();
          if (cleaned.isNotEmpty) steps.add(cleaned);
        } else if (type == 'HowToSection') {
          // Recurse into section items
          final sectionSteps = _parseInstructions(item['itemListElement']);
          steps.addAll(sectionSteps);
        }
      }
    }
    return steps;
  }

  String _stripHtml(String s) {
    return s.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  RecipeIngredient _parseIngredientString(String raw) {
    // Use the shared text parser for "2 kg chicken" style strings
    final parsed = parseTextLine(raw);
    return RecipeIngredient(
      name: parsed.name.isNotEmpty ? parsed.name : raw.trim(),
      quantity: parsed.quantity,
      unit: parsed.unit,
    );
  }

  String? _extractTitle(String html) {
    // Try og:title first
    final ogMatch = RegExp(
      r'<meta[^>]*property\s*=\s*"og:title"[^>]*content\s*=\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (ogMatch != null) return _decodeHtml(ogMatch.group(1)!);

    // Fall back to <title>
    final titleMatch = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    if (titleMatch != null) return _decodeHtml(titleMatch.group(1)!.trim());

    return null;
  }

  String _decodeHtml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }
}
