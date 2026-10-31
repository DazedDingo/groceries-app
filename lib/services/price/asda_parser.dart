import '../../models/price_product.dart';
import 'pack_size.dart';

const String _asdaIndex = 'ASDA_PRODUCTS';

/// Parses an Asda Algolia response into products.
///
/// Accepts the multi-query shape `{results: [{index, hits}]}` (only the
/// ASDA_PRODUCTS index is read) and the single-index shape `{hits: [...]}`.
/// Hits with STATUS other than 'A', or without a positive price, are skipped.
List<PriceProduct> parseAsdaAlgolia(
  Map<String, dynamic> json, {
  required DateTime fetchedAt,
}) {
  final hits = <Map<String, dynamic>>[];
  final results = json['results'];
  if (results is List) {
    for (final r in results) {
      if (r is Map && r['index'] == _asdaIndex && r['hits'] is List) {
        hits.addAll(
          (r['hits'] as List).whereType<Map>().map(
            (m) => Map<String, dynamic>.from(m),
          ),
        );
      }
    }
  } else if (json['hits'] is List) {
    hits.addAll(
      (json['hits'] as List).whereType<Map>().map(
        (m) => Map<String, dynamic>.from(m),
      ),
    );
  }

  final out = <PriceProduct>[];
  final seen = <String>{};
  for (final h in hits) {
    final p = _parseHit(h, fetchedAt);
    if (p != null && seen.add(p.id)) out.add(p);
  }
  return out;
}

PriceProduct? _parseHit(Map<String, dynamic> h, DateTime fetchedAt) {
  if (h['STATUS'] != 'A') return null;
  final id = (h['CIN'] ?? h['ID'])?.toString();
  if (id == null || id.isEmpty) return null;

  final prices = (h['PRICES'] as Map?)?['EN'] as Map?;
  final price = (prices?['PRICE'] as num?)?.toDouble();
  if (price == null || price <= 0) return null;
  final rawWas = (prices?['WASPRICE'] as num?)?.toDouble();
  final wasPrice = (rawWas != null && rawWas > price) ? rawWas : null;
  final offerRaw = prices?['OFFER'] as String?;
  final String? offer = offerRaw == 'Rollback'
      ? 'Rollback'
      : (wasPrice != null ? 'Was £${wasPrice.toStringAsFixed(2)}' : null);

  final brand = ((h['BRAND'] as String?) ?? '').trim();
  final rawName = ((h['NAME'] as String?) ?? '').trim();
  final name =
      (brand.isEmpty || rawName.toLowerCase().startsWith(brand.toLowerCase()))
      ? rawName
      : '$brand $rawName';

  final promos = <PricePromo>[];
  final promoList = (h['PROMOS'] as Map?)?['EN'];
  if (promoList is List) {
    for (final pr in promoList.whereType<Map>()) {
      final end = pr['END_DATE'] as num?;
      final endsAt = end == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (end * 1000).round(),
              isUtc: true,
            );
      // Skip deals that had already finished when we fetched.
      if (endsAt != null && endsAt.isBefore(fetchedAt)) continue;
      promos.add(
        PricePromo.parse(
          id: (pr['ID'] ?? '').toString(),
          name: (pr['NAME'] ?? '').toString(),
          endsAt: endsAt,
        ),
      );
    }
  }

  final stock = h['STOCK'];
  var inStock = true;
  if (stock is Map && stock.isNotEmpty) {
    inStock = stock.values.any((v) => v is num && v > 0);
  }

  // Weight-priced lines (SALES_TYPE other than 'Each') have no fixed pack
  // size, so we leave the quantity unknown rather than guess.
  final salesType = (h['SALES_TYPE'] as String?) ?? 'Each';
  final quantity = salesType == 'Each'
      ? parsePackQuantity(rawName, packSizeField: h['PACK_SIZE'] as String?)
      : null;

  return PriceProduct(
    store: PriceStore.asda,
    id: id,
    brand: brand,
    name: name,
    price: price,
    wasPrice: wasPrice,
    offer: offer,
    promos: promos,
    storeUnitPriceText: prices?['PRICEPERUOMFORMATTED'] as String?,
    quantity: quantity,
    inStock: inStock,
    shelf: (h['PRIMARY_TAXONOMY'] as Map?)?['SHELF_NAME'] as String?,
    aisle: (h['PRIMARY_TAXONOMY'] as Map?)?['AISLE_NAME'] as String?,
    dept: (h['PRIMARY_TAXONOMY'] as Map?)?['DEPT_NAME'] as String?,
    // TODO: placeholder URL pattern; verify against real Asda product pages.
    url: 'https://www.asda.com/groceries/product/$id',
    fetchedAt: fetchedAt,
  );
}
