import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/recipe_search_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('TheMealDB', () {
    test('searchMealDb returns results from live-shaped payload', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'www.themealdb.com');
        expect(req.url.queryParameters['s'], 'pasta');
        return http.Response(
          json.encode({
            'meals': [
              {
                'idMeal': '52771',
                'strMeal': 'Spicy Arrabiata Penne',
                'strMealThumb': 'https://img/penne.jpg',
              },
              {
                'idMeal': '52772',
                'strMeal': 'Pasta Fagioli',
                'strMealThumb': '',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = RecipeSearchService(client: client);

      final results = await service.searchMealDb('pasta');
      expect(results.length, 2);
      expect(results[0].id, '52771');
      expect(results[0].title, 'Spicy Arrabiata Penne');
      expect(results[0].thumbUrl, 'https://img/penne.jpg');
      expect(results[0].source, RecipeSource.mealdb);
      expect(results[1].thumbUrl, isNull, reason: 'empty thumb collapses to null');
    });

    test('searchMealDb returns empty list when meals is null', () async {
      final client = MockClient((req) async =>
          http.Response(json.encode({'meals': null}), 200));
      final service = RecipeSearchService(client: client);
      expect(await service.searchMealDb('zzzzz'), isEmpty);
    });

    test('fetchMealDb maps ingredients and instructions', () async {
      final client = MockClient((req) async {
        return http.Response(
          json.encode({
            'meals': [
              {
                'idMeal': '52771',
                'strMeal': 'Spicy Arrabiata Penne',
                'strCategory': 'Vegetarian',
                'strArea': 'Italian',
                'strInstructions':
                    'Bring a large pot of water to a boil.\nAdd kosher salt to the boiling water.\nAdd pasta.',
                'strSource': 'https://example.com/penne',
                'strIngredient1': 'penne rigate',
                'strMeasure1': '1 pound',
                'strIngredient2': 'olive oil',
                'strMeasure2': '1/4 cup',
                'strIngredient3': '',
                'strMeasure3': '',
              },
            ],
          }),
          200,
        );
      });
      final service = RecipeSearchService(client: client);

      final imported = await service.fetchMealDb('52771');
      expect(imported.name, 'Spicy Arrabiata Penne');
      expect(imported.ingredients.length, 2,
          reason: 'empty slots skipped');
      expect(imported.ingredients[0].name, 'penne rigate');
      expect(imported.instructions.length, 3);
      expect(imported.sourceUrl, 'https://example.com/penne');
      expect(imported.notes, contains('Vegetarian'));
    });

    test('fetchMealDb throws when recipe not found', () async {
      final client = MockClient((req) async =>
          http.Response(json.encode({'meals': null}), 200));
      final service = RecipeSearchService(client: client);
      expect(() => service.fetchMealDb('0'), throwsException);
    });
  });

  group('Spoonacular', () {
    test('searchSpoonacular requires an API key', () async {
      final client = MockClient((req) async => http.Response('{}', 200));
      final service = RecipeSearchService(client: client);
      expect(() => service.searchSpoonacular('pasta', ''), throwsException);
    });

    test('searchSpoonacular returns results', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'api.spoonacular.com');
        expect(req.url.queryParameters['apiKey'], 'KEY-123');
        expect(req.url.queryParameters['query'], 'pasta');
        return http.Response(
          json.encode({
            'results': [
              {'id': 12345, 'title': 'Creamy Pasta', 'image': 'https://img/p.jpg'},
              {'id': 67890, 'title': 'Pesto Pasta', 'image': 'https://img/q.jpg'},
            ],
          }),
          200,
        );
      });
      final service = RecipeSearchService(client: client);
      final results = await service.searchSpoonacular('pasta', 'KEY-123');
      expect(results.length, 2);
      expect(results[0].id, '12345');
      expect(results[0].source, RecipeSource.spoonacular);
    });

    test('searchSpoonacular surfaces 401 with a helpful message', () async {
      final client = MockClient((req) async => http.Response('', 401));
      final service = RecipeSearchService(client: client);
      expect(
        () => service.searchSpoonacular('x', 'bad-key'),
        throwsA(predicate((e) => e.toString().contains('invalid key'))),
      );
    });

    test('fetchSpoonacular maps extendedIngredients + analyzedInstructions',
        () async {
      final client = MockClient((req) async {
        return http.Response(
          json.encode({
            'title': 'Creamy Pasta',
            'sourceUrl': 'https://example.com/p',
            'extendedIngredients': [
              {'name': 'penne', 'amount': 200, 'unit': 'g'},
              {'name': 'cream', 'amount': 1.5, 'unit': 'cup'},
              {'name': '', 'amount': 1, 'unit': 'kg'},
            ],
            'analyzedInstructions': [
              {
                'steps': [
                  {'step': 'Boil water.'},
                  {'step': 'Add pasta.'},
                ],
              },
            ],
          }),
          200,
        );
      });
      final service = RecipeSearchService(client: client);
      final imported = await service.fetchSpoonacular('12345', 'KEY');
      expect(imported.name, 'Creamy Pasta');
      expect(imported.ingredients.length, 2, reason: 'empty name skipped');
      expect(imported.ingredients[0].name, 'penne');
      expect(imported.ingredients[0].unit, 'g');
      expect(imported.ingredients[1].quantity, 2,
          reason: '1.5 cups rounds to 2');
      expect(imported.instructions, ['Boil water.', 'Add pasta.']);
      expect(imported.sourceUrl, 'https://example.com/p');
    });

    test('fetchSpoonacular falls back to plain-text instructions', () async {
      final client = MockClient((req) async => http.Response(
            json.encode({
              'title': 'Soup',
              'extendedIngredients': [],
              'analyzedInstructions': [],
              'instructions':
                  '<p>Chop onions. Simmer broth. Serve hot.</p>',
            }),
            200,
          ));
      final service = RecipeSearchService(client: client);
      final imported = await service.fetchSpoonacular('x', 'KEY');
      expect(imported.instructions.length, 3);
      expect(imported.instructions.first, 'Chop onions');
    });
  });
}
