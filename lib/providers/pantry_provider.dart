import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pantry_service.dart';
import '../services/location_service.dart';
import '../models/pantry_item.dart';
import 'household_provider.dart';

final pantryServiceProvider = Provider<PantryService>((ref) => PantryService());

final pantryProvider = StreamProvider<List<PantryItem>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(pantryServiceProvider).pantryStream(householdId);
});

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final customLocationsProvider = StreamProvider<List<String>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(locationServiceProvider).customLocationsStream(householdId);
});

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

/// How the pantry screen groups items. `status` is the original layout
/// (Expired → Needs restock → Stocked). `category` and `location` swap that
/// out for a flat list with headers per category or per location.
enum PantryGrouping {
  status('status', 'Status'),
  category('category', 'Category'),
  location('location', 'Location');

  final String id;
  final String label;
  const PantryGrouping(this.id, this.label);

  static PantryGrouping fromId(String? id) {
    for (final g in PantryGrouping.values) {
      if (g.id == id) return g;
    }
    return PantryGrouping.status;
  }
}

final pantryGroupingProvider =
    StateNotifierProvider<PantryGroupingNotifier, PantryGrouping>((ref) {
  return PantryGroupingNotifier();
});

class PantryGroupingNotifier extends StateNotifier<PantryGrouping> {
  PantryGroupingNotifier() : super(PantryGrouping.status) {
    _load();
  }

  static const _prefsKey = 'pantryGrouping';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = PantryGrouping.fromId(prefs.getString(_prefsKey));
  }

  Future<void> set(PantryGrouping grouping) async {
    state = grouping;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, grouping.id);
  }
}
