import '../../models/price_product.dart';
import 'pack_size.dart';

const String _costcoBase = 'https://www.costco.co.uk';

/// Parses a Costco UK search response (`{products: [...]}`) into products we
/// can actually order: membership-restricted, business-delivery, unpriced and
/// non-purchasable items are dropped. Costco's own `pricePerUnit` is ignored
/// (units are mixed); quantity comes from the product name.
List<PriceProduct> parseCostcoSearch(
  Map<String, dynamic> json, {
  required DateTime fetchedAt,
}) {
  final products = json['products'];
  if (products is! List) return const [];
  final out = <PriceProduct>[];
  final seen = <String>{};
  for (final raw in products.whereType<Map>()) {
    final p = Map<String, dynamic>.from(raw);
    if (p['membershipRestrictionApplied'] == true) continue;
    if (p['businessDelivery'] == true) continue;
    if (p['purchasable'] == false) continue;
    final price = ((p['price'] as Map?)?['value'] as num?)?.toDouble();
    if (price == null || price <= 0) continue;
    final id = p['code']?.toString();
    final name = (p['name'] as String?)?.trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
    if (!seen.add(id)) continue;

    final promos = <PricePromo>[];
    final pp = p['potentialPromotions'];
    if (pp is List) {
      for (final pr in pp.whereType<Map>()) {
        final text = (pr['description'] ?? pr['name'] ?? '').toString();
        if (text.isEmpty) continue;
        promos.add(
          PricePromo.parse(
            id: (pr['code'] ?? pr['id'] ?? '').toString(),
            name: text,
            endsAt: priceDateFromAny(pr['endDate']),
          ),
        );
      }
    }

    final status = (p['stock'] as Map?)?['stockLevelStatus'] as String?;
    final url = p['url'] as String?;
    out.add(
      PriceProduct(
        store: PriceStore.costco,
        id: id,
        brand: '',
        name: name,
        price: price,
        promos: promos,
        quantity: parsePackQuantity(name),
        inStock: status != 'outOfStock',
        url: url == null ? null : '$_costcoBase$url',
        fetchedAt: fetchedAt,
      ),
    );
  }
  return out;
}
