import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/asda_client.dart';
import 'package:groceries_app/services/price/asda_parser.dart';
import 'package:groceries_app/services/price/costco_client.dart';
import 'package:groceries_app/services/price/costco_parser.dart';
import 'package:groceries_app/services/price/price_fetch_exception.dart';

final fixtureFetched = DateTime.utc(2026, 10, 31, 12);

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final Map<String, dynamic> asdaFixture = _json(
  'test/fixtures/price/asda_algolia_queries.json',
);
final Map<String, dynamic> costcoFixture = _json(
  'test/fixtures/price/costco_search.json',
);

/// The 12 fixture terms (Asda search term -> Costco fixture key).
const fixtureTerms = {
  'milk': 'milk',
  'basmati rice': 'basmati rice',
  'toilet roll': 'toilet tissue',
  'kitchen roll': 'kitchen roll',
  'spaghetti': 'pasta',
  'baked beans': 'baked beans',
  'chopped tomatoes': 'chopped tomatoes',
  'tea bags': 'tea bags',
  'olive oil': 'olive oil',
  'laundry liquid': 'washing liquid',
  'dishwasher tablets': 'dishwasher tablets',
  'cereal': 'cereal',
};

ShoppingItem shoppingItem(String name, {int qty = 1, String id = ''}) =>
    ShoppingItem(
      id: id.isEmpty ? name : id,
      name: name,
      quantity: qty,
      categoryId: 'uncategorised',
      preferredStores: const [],
      pantryItemId: null,
      addedBy: const AddedBy(
        uid: 'u1',
        displayName: 'Alice',
        source: ItemSource.app,
      ),
      addedAt: fixtureFetched,
    );

class FakeAsdaSearch implements AsdaSearch {
  final List<String> calls = [];
  Object? failWith;

  /// Terms (lower-case) that throw [failWith] while others succeed.
  final Set<String> failTerms = {};

  /// Overrides per lower-case term; checked before the fixture.
  final Map<String, List<PriceProduct>> overrides = {};

  /// When set, each search waits for this before answering.
  Future<void> Function()? gate;
  bool disposed = false;

  @override
  Future<List<PriceProduct>> search(String term) async {
    calls.add(term);
    if (gate != null) await gate!();
    final key = term.toLowerCase().trim();
    if (failWith != null && (failTerms.isEmpty || failTerms.contains(key))) {
      throw failWith!;
    }
    if (overrides.containsKey(key)) return overrides[key]!;
    return asdaFixture.containsKey(key)
        ? parseAsdaAlgolia(
            asdaFixture[key] as Map<String, dynamic>,
            fetchedAt: fixtureFetched,
          )
        : const [];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeCostcoSearch implements CostcoSearch {
  final List<String> calls = [];
  Object? failWith;

  /// Terms (lower-case) that throw [failWith] while others succeed.
  final Set<String> failTerms = {};
  final Map<String, List<PriceProduct>> overrides = {};
  Future<void> Function()? gate;

  @override
  Future<List<PriceProduct>> search(String term) async {
    calls.add(term);
    if (gate != null) await gate!();
    final key = term.toLowerCase().trim();
    if (failWith != null && (failTerms.isEmpty || failTerms.contains(key))) {
      throw failWith!;
    }
    if (overrides.containsKey(key)) return overrides[key]!;
    final fixKey = fixtureTerms[key] ?? key;
    return costcoFixture.containsKey(fixKey)
        ? parseCostcoSearch(
            costcoFixture[fixKey] as Map<String, dynamic>,
            fetchedAt: fixtureFetched,
          )
        : const [];
  }
}

const asdaTimeout = PriceFetchException(PriceStore.asda, 'Asda timed out');
