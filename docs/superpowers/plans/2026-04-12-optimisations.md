# Groceries App Optimisations Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 7 optimisations — pantry category filters/sorting, dead-code cleanup, overflow fix, Google Wallet link, and a full recipes feature.

**Architecture:** Flutter/Riverpod frontend, Firebase Firestore backend. Each task produces a standalone commit. Recipes is a new Firestore subcollection under households with a new nav tab.

**Tech Stack:** Flutter 3.11, Riverpod 2, Cloud Firestore, GoRouter, Material 3 dark theme.

---

## File Map

| Area | Files | Action |
|------|-------|--------|
| Pantry overflow fix | `lib/screens/pantry/widgets/pantry_item_tile.dart` | Modify |
| Dead price code | `lib/screens/prices/`, `lib/services/prices_service.dart`, `lib/providers/prices_provider.dart`, `lib/models/price_snapshot.dart`, `lib/models/store.dart`, `lib/services/stores_service.dart`, `lib/providers/stores_provider.dart`, `lib/screens/settings/manage_stores_screen.dart` | Delete (prices dir, prices_service, prices_provider, price_snapshot) |
| Pantry sort + filter | `lib/providers/pantry_provider.dart`, `lib/screens/pantry/pantry_screen.dart` | Modify |
| Google Wallet link | `lib/screens/settings/settings_screen.dart`, `pubspec.yaml` | Modify |
| Recipe model | `lib/models/recipe.dart` | Create |
| Recipe service | `lib/services/recipes_service.dart` | Create |
| Recipe provider | `lib/providers/recipes_provider.dart` | Create |
| Recipes screen | `lib/screens/recipes/recipes_screen.dart` | Create |
| Recipe detail screen | `lib/screens/recipes/recipe_detail_screen.dart` | Create |
| Recipe form screen | `lib/screens/recipes/add_recipe_screen.dart` | Create |
| Firestore rules | `firestore.rules` | Modify |
| Router + nav | `lib/app.dart` | Modify |
| Tests | `test/services/recipes_service_test.dart`, `test/models/recipe_test.dart` | Create |

---

### Task 1: Fix pantry "Add to list" overflow (Opt 4)

**Files:**
- Modify: `lib/screens/pantry/widgets/pantry_item_tile.dart`

The `trailing` Row has unconstrained width. When the "Add to list" button appears at qty 0, it overflows. The fix is to move "Add to list" out of the trailing row and into a subtitle action, or constrain the trailing width properly.

- [ ] **Step 1: Fix the layout**

Replace the current `trailing` in `pantry_item_tile.dart` with a layout that doesn't overflow. Move the "Add to list" button from the trailing Row into the subtitle area:

```dart
@override
Widget build(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return ListTile(
    onTap: onTap,
    title: Row(
      children: [
        Expanded(child: Text(item.name)),
        Chip(
          label: Text(categoryName,
              style: Theme.of(context).textTheme.labelSmall),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        if (item.isBelowOptimal) ...[
          const SizedBox(width: 6),
          Icon(Icons.warning_amber, size: 16, color: scheme.error),
        ],
      ],
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${item.currentQuantity} / ${item.optimalQuantity} optimal'),
        if (item.isBelowOptimal)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: onAddToList,
                icon: const Icon(Icons.add_shopping_cart, size: 14),
                label: const Text('Add to list'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: onDecrement,
          visualDensity: VisualDensity.compact,
        ),
        Text('${item.currentQuantity}', style: const TextStyle(fontSize: 16)),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: onIncrement,
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}
```

- [ ] **Step 2: Verify no overflow**

Run: `flutter analyze`
Expected: No errors. The "Add to list" button is now below the subtitle text, not crammed into the trailing Row.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/pantry/widgets/pantry_item_tile.dart
git commit -m "fix: move 'Add to list' to subtitle to prevent trailing overflow"
```

---

### Task 2: Remove dead price-tracking code (Opt 5)

**Files:**
- Delete: `lib/screens/prices/prices_screen.dart`
- Delete: `lib/screens/prices/widgets/price_panel.dart`
- Delete: `lib/services/prices_service.dart`
- Delete: `lib/providers/prices_provider.dart`
- Delete: `lib/models/price_snapshot.dart`

The price tab was removed from nav in commit 192089e, but the files still exist. No other file imports from these modules (the route was removed from `app.dart`).

- [ ] **Step 1: Verify no remaining imports**

Run: `grep -r "prices_provider\|prices_service\|price_snapshot\|prices_screen\|price_panel" lib/`
Expected: Only hits in the files being deleted (self-references).

- [ ] **Step 2: Delete the files**

```bash
rm lib/screens/prices/prices_screen.dart
rm lib/screens/prices/widgets/price_panel.dart
rmdir lib/screens/prices/widgets
rmdir lib/screens/prices
rm lib/services/prices_service.dart
rm lib/providers/prices_provider.dart
rm lib/models/price_snapshot.dart
```

- [ ] **Step 3: Remove prices Firestore rule**

In `firestore.rules`, delete the prices match block:

```
      match /prices/{pantryItemId}/snapshots/{snapshotId} {
        allow read: if isMember(householdId);
        allow write: if false;
      }
```

- [ ] **Step 4: Verify build**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove dead price-tracking code and Firestore rules"
```

---

### Task 3: Add category filter + sort to Pantry tab (Opt 2 + 3 + 3a)

**Files:**
- Modify: `lib/providers/pantry_provider.dart`
- Modify: `lib/screens/pantry/pantry_screen.dart`
- Modify: `lib/providers/items_provider.dart` (sort shopping list by category too)

Currently the pantry groups by "needs restocking" vs "stocked". We'll add a filter bar (reusing the pattern from `filter_bar.dart`) and sort within each group by category name, so when you're at the store you can go aisle-by-aisle.

The shopping list already groups by `categoryId` — we need to sort those groups by category name (currently they appear in insertion order).

- [ ] **Step 1: Add pantry filter + sorted provider**

In `lib/providers/pantry_provider.dart`, add:

```dart
final pantrySelectedCategoryProvider = StateProvider<String?>((ref) => null);

final filteredPantryProvider = Provider<List<PantryItem>>((ref) {
  final pantry = ref.watch(pantryProvider).value ?? [];
  final category = ref.watch(pantrySelectedCategoryProvider);
  var items = pantry.toList();
  if (category != null) {
    items = items.where((p) => p.categoryId == category).toList();
  }
  return items;
});
```

- [ ] **Step 2: Update pantry screen to use filter + group by category within restock sections**

In `lib/screens/pantry/pantry_screen.dart`:

1. Import `categories_provider.dart` (already imported), `filteredPantryProvider`, `pantrySelectedCategoryProvider`.
2. Replace `ref.watch(pantryProvider).value ?? []` with `ref.watch(filteredPantryProvider)`.
3. Add a filter bar of category FilterChips at top of body (similar to shopping list).
4. Within "Needs restocking" and "Stocked" sections, sub-group items by category and show category headers with color pips.

The build method becomes:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final pantry = ref.watch(filteredPantryProvider);
  final householdId = ref.watch(householdIdProvider).value ?? '';
  final categories = ref.watch(categoriesProvider).value ?? [];
  final pantryService = ref.watch(pantryServiceProvider);
  final itemsService = ref.watch(itemsServiceProvider);
  final user = ref.watch(authStateProvider).value;
  final selectedCat = ref.watch(pantrySelectedCategoryProvider);

  final needsRestock = pantry.where((p) => p.isBelowOptimal).toList();
  final stocked = pantry.where((p) => !p.isBelowOptimal).toList();

  // Sort each section by category name
  String catSortKey(PantryItem p) {
    try {
      return categories.firstWhere((c) => c.id == p.categoryId).name;
    } catch (_) {
      return 'zzz'; // uncategorised last
    }
  }
  needsRestock.sort((a, b) => catSortKey(a).compareTo(catSortKey(b)));
  stocked.sort((a, b) => catSortKey(a).compareTo(catSortKey(b)));

  // ... rest of build with filter bar at top
```

Add a filter bar widget above the ListView (inside a Column > Expanded pattern):

```dart
body: Column(
  children: [
    // Category filter chips
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: categories.map((c) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
            label: Text(c.name),
            selected: selectedCat == c.id,
            selectedColor: c.color.withValues(alpha: 0.3),
            onSelected: (_) => ref.read(pantrySelectedCategoryProvider.notifier).state =
                selectedCat == c.id ? null : c.id,
          ),
        )).toList(),
      ),
    ),
    Expanded(
      child: pantry.isEmpty
          ? const Center(child: Text('No pantry items yet. Tap + to add one.'))
          : ListView(children: [ /* ... existing sections ... */ ]),
    ),
  ],
),
```

- [ ] **Step 3: Sort shopping list category groups by name**

In `lib/screens/shopping_list/shopping_list_screen.dart`, the `grouped` map entries are iterated in insertion order. Sort them by category name before rendering:

```dart
final sortedGroups = grouped.entries.toList()
  ..sort((a, b) {
    final catA = categories.firstWhere(
      (c) => c.id == a.key,
      orElse: () => const GroceryCategory(id: '', name: 'zzz', color: Color(0xFF546E7A), addedBy: ''),
    );
    final catB = categories.firstWhere(
      (c) => c.id == b.key,
      orElse: () => const GroceryCategory(id: '', name: 'zzz', color: Color(0xFF546E7A), addedBy: ''),
    );
    return catA.name.compareTo(catB.name);
  });
```

Then iterate `sortedGroups` instead of `grouped.entries` in the ListView builder.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/pantry_provider.dart lib/screens/pantry/pantry_screen.dart lib/screens/shopping_list/shopping_list_screen.dart
git commit -m "feat: add category filters to pantry, sort both tabs by category for aisle shopping"
```

---

### Task 4: Add Google Wallet quick link (Opt 6)

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`
- Modify: `pubspec.yaml` (add `url_launcher`)

This adds a settings entry that launches Google Wallet via intent. On Android, `com.google.android.apps.walletnfcrel` is the Google Wallet package.

- [ ] **Step 1: Add url_launcher dependency**

In `pubspec.yaml` under `dependencies`, add:
```yaml
  url_launcher: ^6.2.5
```

Run: `flutter pub get`

- [ ] **Step 2: Add the settings tile**

In `lib/screens/settings/settings_screen.dart`, add import and tile:

```dart
import 'package:url_launcher/url_launcher.dart';
```

Add this tile after the "Share invite link" ListTile:

```dart
ListTile(
  leading: const Icon(Icons.wallet),
  title: const Text('Open Google Wallet'),
  subtitle: const Text('Quick access to store loyalty cards'),
  onTap: () async {
    final uri = Uri.parse('https://wallet.google.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Wallet')),
      );
    }
  },
),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/screens/settings/settings_screen.dart
git commit -m "feat: add Google Wallet quick link in settings"
```

---

### Task 5: Recipe model + Firestore rules (Opt 7 — data layer)

**Files:**
- Create: `lib/models/recipe.dart`
- Modify: `firestore.rules`
- Create: `test/models/recipe_test.dart`

A recipe has a name, list of ingredients (each with a name, quantity, and optional categoryId), and optional notes. Stored at `households/{id}/recipes/{recipeId}`.

- [ ] **Step 1: Write the model test**

Create `test/models/recipe_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/recipe.dart';

void main() {
  group('RecipeIngredient', () {
    test('toMap round-trips', () {
      final ing = RecipeIngredient(name: 'Flour', quantity: 2, categoryId: 'bakery');
      final map = ing.toMap();
      expect(map['name'], 'Flour');
      expect(map['quantity'], 2);
      expect(map['categoryId'], 'bakery');
    });

    test('fromMap with defaults', () {
      final ing = RecipeIngredient.fromMap({'name': 'Salt'});
      expect(ing.quantity, 1);
      expect(ing.categoryId, isNull);
    });
  });

  group('Recipe', () {
    test('toMap includes all fields', () {
      final recipe = Recipe(
        id: 'r1',
        name: 'Pasta',
        ingredients: [
          RecipeIngredient(name: 'Spaghetti', quantity: 1, categoryId: null),
          RecipeIngredient(name: 'Tomato sauce', quantity: 2, categoryId: 'canned'),
        ],
        notes: 'Cook 10 mins',
      );
      final map = recipe.toMap();
      expect(map['name'], 'Pasta');
      expect((map['ingredients'] as List).length, 2);
      expect(map['notes'], 'Cook 10 mins');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/recipe_test.dart`
Expected: FAIL — `recipe.dart` doesn't exist yet.

- [ ] **Step 3: Write the model**

Create `lib/models/recipe.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/recipe_test.dart`
Expected: PASS.

- [ ] **Step 5: Add Firestore rules for recipes**

In `firestore.rules`, inside the `match /households/{householdId}` block, add after the history rule:

```
      match /recipes/{recipeId} {
        allow read, write: if isMember(householdId);
      }
```

- [ ] **Step 6: Commit**

```bash
git add lib/models/recipe.dart test/models/recipe_test.dart firestore.rules
git commit -m "feat: add Recipe model with Firestore rules"
```

---

### Task 6: Recipe service + provider (Opt 7 — service layer)

**Files:**
- Create: `lib/services/recipes_service.dart`
- Create: `lib/providers/recipes_provider.dart`
- Create: `test/services/recipes_service_test.dart`

- [ ] **Step 1: Write the service test**

Create `test/services/recipes_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:groceries_app/services/recipes_service.dart';
import 'package:groceries_app/models/recipe.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late RecipesService service;
  const hid = 'test-household';

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    service = RecipesService(db: fakeDb);
  });

  test('addRecipe creates doc and stream emits it', () async {
    final id = await service.addRecipe(
      householdId: hid,
      name: 'Pancakes',
      ingredients: [
        RecipeIngredient(name: 'Flour', quantity: 2, categoryId: 'bakery'),
        RecipeIngredient(name: 'Eggs', quantity: 3, categoryId: 'dairy'),
      ],
      notes: 'Mix well',
    );
    expect(id, isNotEmpty);

    final recipes = await service.recipesStream(hid).first;
    expect(recipes.length, 1);
    expect(recipes.first.name, 'Pancakes');
    expect(recipes.first.ingredients.length, 2);
    expect(recipes.first.notes, 'Mix well');
  });

  test('updateRecipe changes fields', () async {
    final id = await service.addRecipe(
      householdId: hid,
      name: 'Old Name',
      ingredients: [RecipeIngredient(name: 'A', quantity: 1)],
    );
    await service.updateRecipe(
      householdId: hid,
      recipeId: id,
      name: 'New Name',
      ingredients: [RecipeIngredient(name: 'B', quantity: 2)],
      notes: 'Updated',
    );

    final recipes = await service.recipesStream(hid).first;
    expect(recipes.first.name, 'New Name');
    expect(recipes.first.ingredients.first.name, 'B');
  });

  test('deleteRecipe removes doc', () async {
    final id = await service.addRecipe(
      householdId: hid,
      name: 'ToDelete',
      ingredients: [],
    );
    await service.deleteRecipe(householdId: hid, recipeId: id);

    final recipes = await service.recipesStream(hid).first;
    expect(recipes, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/recipes_service_test.dart`
Expected: FAIL — `recipes_service.dart` doesn't exist.

- [ ] **Step 3: Write the service**

Create `lib/services/recipes_service.dart`:

```dart
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
    String? notes,
  }) async {
    final ref = await _db.collection('households/$householdId/recipes').add({
      'name': name,
      'ingredients': ingredients.map((i) => i.toMap()).toList(),
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateRecipe({
    required String householdId,
    required String recipeId,
    required String name,
    required List<RecipeIngredient> ingredients,
    String? notes,
  }) async {
    await _db.doc('households/$householdId/recipes/$recipeId').update({
      'name': name,
      'ingredients': ingredients.map((i) => i.toMap()).toList(),
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteRecipe({
    required String householdId,
    required String recipeId,
  }) async {
    await _db.doc('households/$householdId/recipes/$recipeId').delete();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/recipes_service_test.dart`
Expected: All 3 PASS.

- [ ] **Step 5: Write the provider**

Create `lib/providers/recipes_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/recipes_service.dart';
import '../models/recipe.dart';
import 'household_provider.dart';

final recipesServiceProvider = Provider<RecipesService>((ref) => RecipesService());

final recipesProvider = StreamProvider<List<Recipe>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(recipesServiceProvider).recipesStream(householdId);
});
```

- [ ] **Step 6: Commit**

```bash
git add lib/services/recipes_service.dart lib/providers/recipes_provider.dart test/services/recipes_service_test.dart
git commit -m "feat: add RecipesService with CRUD and Riverpod provider"
```

---

### Task 7: Recipes screen — list + "Cook this" (Opt 7 — UI)

**Files:**
- Create: `lib/screens/recipes/recipes_screen.dart`
- Create: `lib/screens/recipes/recipe_detail_screen.dart`
- Modify: `lib/app.dart` (add routes, nav tab)

- [ ] **Step 1: Create the recipes list screen**

Create `lib/screens/recipes/recipes_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      body: recipes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No recipes yet. Tap + to create one.'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              return ListTile(
                title: Text(r.name),
                subtitle: Text('${r.ingredients.length} ingredients'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/recipes/${r.id}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/recipes/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 2: Create the recipe detail screen with "Cook this"**

Create `lib/screens/recipes/recipe_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../models/item.dart';

class RecipeDetailScreen extends ConsumerWidget {
  final String recipeId;
  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider).value ?? [];
    final recipe = recipes.where((r) => r.id == recipeId).firstOrNull;
    final householdId = ref.watch(householdIdProvider).value ?? '';

    if (recipe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Recipe not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.go('/recipes/${recipe.id}/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete recipe?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(recipesServiceProvider).deleteRecipe(
                  householdId: householdId,
                  recipeId: recipe.id,
                );
                if (context.mounted) context.go('/recipes');
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (recipe.notes != null && recipe.notes!.isNotEmpty) ...[
            Text(recipe.notes!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
          ],
          Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...recipe.ingredients.map((ing) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(ing.name),
            trailing: Text('x${ing.quantity}'),
          )),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _cookThis(context, ref, householdId),
            icon: const Icon(Icons.restaurant),
            label: const Text('Cook this'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cookThis(BuildContext context, WidgetRef ref, String householdId) async {
    final recipes = ref.read(recipesProvider).value ?? [];
    final recipe = recipes.where((r) => r.id == recipeId).firstOrNull;
    if (recipe == null) return;

    final user = ref.read(authStateProvider).value;
    final itemsService = ref.read(itemsServiceProvider);

    for (final ing in recipe.ingredients) {
      await itemsService.addItem(
        householdId: householdId,
        name: ing.name,
        categoryId: ing.categoryId ?? 'uncategorised',
        preferredStores: [],
        pantryItemId: null,
        quantity: ing.quantity,
        addedBy: AddedBy(
          uid: user?.uid,
          displayName: user?.displayName ?? 'Unknown',
          source: ItemSource.app,
        ),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${recipe.ingredients.length} items to shopping list')),
      );
    }
  }
}
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/recipes/
git commit -m "feat: add recipes list and detail screens with Cook This action"
```

---

### Task 8: Add recipe form screen (Opt 7 — create/edit)

**Files:**
- Create: `lib/screens/recipes/add_recipe_screen.dart`

- [ ] **Step 1: Create the add/edit recipe screen**

Create `lib/screens/recipes/add_recipe_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/categories_provider.dart';
import '../../models/recipe.dart';
import '../../services/category_guesser.dart';

class AddRecipeScreen extends ConsumerStatefulWidget {
  final String? recipeId;
  const AddRecipeScreen({super.key, this.recipeId});

  @override
  ConsumerState<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends ConsumerState<AddRecipeScreen> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_IngredientEntry> _ingredients = [];
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    for (final e in _ingredients) { e.nameCtrl.dispose(); }
    super.dispose();
  }

  void _initFromRecipe(Recipe recipe) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = recipe.name;
    _notesCtrl.text = recipe.notes ?? '';
    for (final ing in recipe.ingredients) {
      _ingredients.add(_IngredientEntry(
        nameCtrl: TextEditingController(text: ing.name),
        quantity: ing.quantity,
        categoryId: ing.categoryId,
      ));
    }
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(_IngredientEntry(nameCtrl: TextEditingController()));
    });
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredients[index].nameCtrl.dispose();
      _ingredients.removeAt(index);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _ingredients.isEmpty) return;

    final householdId = ref.read(householdIdProvider).value ?? '';
    final service = ref.read(recipesServiceProvider);
    final ingredients = _ingredients.map((e) => RecipeIngredient(
      name: e.nameCtrl.text.trim(),
      quantity: e.quantity,
      categoryId: e.categoryId,
    )).where((i) => i.name.isNotEmpty).toList();

    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    if (widget.recipeId != null) {
      await service.updateRecipe(
        householdId: householdId,
        recipeId: widget.recipeId!,
        name: name,
        ingredients: ingredients,
        notes: notes,
      );
    } else {
      await service.addRecipe(
        householdId: householdId,
        name: name,
        ingredients: ingredients,
        notes: notes,
      );
    }

    if (mounted) context.go('/recipes');
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? [];

    // If editing, initialize from existing recipe
    if (widget.recipeId != null) {
      final recipes = ref.watch(recipesProvider).value ?? [];
      final existing = recipes.where((r) => r.id == widget.recipeId).firstOrNull;
      if (existing != null) _initFromRecipe(existing);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipeId != null ? 'Edit Recipe' : 'New Recipe'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Recipe name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addIngredient,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          ..._ingredients.asMap().entries.map((entry) {
            final i = entry.key;
            final ing = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: ing.nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Ingredient ${i + 1}',
                        isDense: true,
                      ),
                      onChanged: (val) {
                        final guess = guessCategory(val, categories);
                        if (guess != null) {
                          setState(() => ing.categoryId = guess.id);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: ing.quantity > 1
                              ? () => setState(() => ing.quantity--)
                              : null,
                          child: const Icon(Icons.remove, size: 18),
                        ),
                        Expanded(
                          child: Text(
                            '${ing.quantity}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => ing.quantity++),
                          child: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeIngredient(i),
                  ),
                ],
              ),
            );
          }),
          if (_ingredients.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('Tap "Add" to add ingredients',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
        ],
      ),
    );
  }
}

class _IngredientEntry {
  final TextEditingController nameCtrl;
  int quantity;
  String? categoryId;

  _IngredientEntry({required this.nameCtrl, this.quantity = 1, this.categoryId});
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/recipes/add_recipe_screen.dart
git commit -m "feat: add recipe create/edit form with ingredient management"
```

---

### Task 9: Wire recipes into router + navigation (Opt 7 — integration)

**Files:**
- Modify: `lib/app.dart`

- [ ] **Step 1: Add routes and nav tab**

In `lib/app.dart`:

1. Add imports:
```dart
import 'screens/recipes/recipes_screen.dart';
import 'screens/recipes/recipe_detail_screen.dart';
import 'screens/recipes/add_recipe_screen.dart';
```

2. Add recipe routes inside the ShellRoute's routes list, after the pantry routes:
```dart
GoRoute(
  path: '/recipes',
  builder: (_, __) => const RecipesScreen(),
  routes: [
    GoRoute(
      path: 'new',
      builder: (_, __) => const AddRecipeScreen(),
    ),
    GoRoute(
      path: ':recipeId',
      builder: (_, state) => RecipeDetailScreen(
        recipeId: state.pathParameters['recipeId']!,
      ),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (_, state) => AddRecipeScreen(
            recipeId: state.pathParameters['recipeId'],
          ),
        ),
      ],
    ),
  ],
),
```

3. Update `ScaffoldWithNavBar` — add the recipes tab and update index mapping:

```dart
// Update selectedIndex logic
int selectedIndex = 0;
if (location.startsWith('/pantry')) selectedIndex = 1;
if (location.startsWith('/recipes')) selectedIndex = 2;
if (location.startsWith('/settings')) selectedIndex = 3;
```

Add the Recipes destination to NavigationBar:
```dart
destinations: const [
  NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'List'),
  NavigationDestination(icon: Icon(Icons.kitchen), label: 'Pantry'),
  NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Recipes'),
  NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
],
```

Update routes array:
```dart
const routes = ['/list', '/pantry', '/recipes', '/settings'];
```

- [ ] **Step 2: Verify**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/app.dart
git commit -m "feat: wire recipes tab into navigation and router"
```

---

### Task 10: Deploy Firestore rules

**Files:** (none — deployment only)

- [ ] **Step 1: Deploy updated rules**

Run: `firebase deploy --only firestore:rules`
Expected: Successfully deployed.

- [ ] **Step 2: Commit** (no code changes — just verify)

Already committed in prior tasks.

---

## Summary of Optimisations

| # | Optimisation | Task(s) |
|---|-------------|---------|
| 1 | Categories — already exist; subcategories not needed for MVP | Existing |
| 2 | Pantry category filters | Task 3 |
| 3 | Sort by category (both tabs) | Task 3 |
| 3a | Aisle-by-aisle shopping | Task 3 |
| 4 | Pantry qty 0 overflow fix | Task 1 |
| 5 | Remove dead price code | Task 2 |
| 6 | Google Wallet link | Task 4 |
| 7 | Recipes tab | Tasks 5–9 |
