import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/price/promo_parser.dart';

enum PriceStore { asda, costco }

extension PriceStoreExt on PriceStore {
  String get value => switch (this) {
    PriceStore.asda => 'asda',
    PriceStore.costco => 'costco',
  };
  static PriceStore fromString(String s) => switch (s) {
    'costco' => PriceStore.costco,
    _ => PriceStore.asda,
  };
}

/// Lenient date reader for stored maps: Timestamp, DateTime, ISO string or
/// epoch millis.
DateTime? priceDateFromAny(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

/// How much is in a pack. Any subset of fields may be set.
///
/// [countUnit] is a normalised singular unit: 'wash', 'bag', 'roll',
/// 'tablet', 'pod', 'capsule', 'sheet', 'serving', 'wipe' or 'each'.
class PackQuantity {
  final double? grams;
  final double? millilitres;
  final double? count;
  final String? countUnit;

  const PackQuantity({
    this.grams,
    this.millilitres,
    this.count,
    this.countUnit,
  });

  Map<String, dynamic> toMap() => {
    'grams': grams,
    'millilitres': millilitres,
    'count': count,
    'countUnit': countUnit,
  };

  factory PackQuantity.fromMap(Map<String, dynamic> d) => PackQuantity(
    grams: (d['grams'] as num?)?.toDouble(),
    millilitres: (d['millilitres'] as num?)?.toDouble(),
    count: (d['count'] as num?)?.toDouble(),
    countUnit: d['countUnit'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is PackQuantity &&
      other.grams == grams &&
      other.millilitres == millilitres &&
      other.count == count &&
      other.countUnit == countUnit;

  @override
  int get hashCode => Object.hash(grams, millilitres, count, countUnit);

  @override
  String toString() =>
      'PackQuantity(grams: $grams, ml: $millilitres, count: $count $countUnit)';
}

class PricePromo {
  final String id;
  final String name;
  final DateTime? endsAt;

  /// Parsed from [name]; null when the promo isn't a recognised multi-buy.
  final MultiBuy? multiBuy;

  const PricePromo({
    required this.id,
    required this.name,
    this.endsAt,
    this.multiBuy,
  });

  /// Builds a promo, parsing the multi-buy out of [name].
  factory PricePromo.parse({
    required String id,
    required String name,
    DateTime? endsAt,
  }) => PricePromo(
    id: id,
    name: name,
    endsAt: endsAt,
    multiBuy: parseMultiBuy(name),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt!),
  };

  factory PricePromo.fromMap(Map<String, dynamic> d) => PricePromo.parse(
    id: (d['id'] ?? '').toString(),
    name: (d['name'] ?? '').toString(),
    endsAt: priceDateFromAny(d['endsAt']),
  );
}

class PriceProduct {
  final PriceStore store;
  final String id;
  final String brand;

  /// Display name (brand + name for Asda unless the name already starts with
  /// the brand).
  final String name;
  final double price;

  /// Only set when strictly greater than [price].
  final double? wasPrice;

  /// 'Rollback', a 'Was £x' label, or null for a plain list price.
  final String? offer;
  final List<PricePromo> promos;

  /// The store's own unit price text, e.g. "£1.06/LT". Display only.
  final String? storeUnitPriceText;
  final PackQuantity? quantity;
  final bool inStock;

  /// Asda SHELF_NAME.
  final String? shelf;

  /// Asda AISLE_NAME (the group of shelves the shelf sits in). Null for
  /// Costco.
  final String? aisle;

  /// Asda DEPT_NAME (the group of aisles). Null for Costco.
  final String? dept;
  final String? url;
  final DateTime fetchedAt;

  /// True when a price refresh could not find this product any more, so
  /// [price] is the last known one and may be out of date.
  final bool stale;

  const PriceProduct({
    required this.store,
    required this.id,
    this.brand = '',
    required this.name,
    required this.price,
    this.wasPrice,
    this.offer,
    this.promos = const [],
    this.storeUnitPriceText,
    this.quantity,
    this.inStock = true,
    this.shelf,
    this.aisle,
    this.dept,
    this.url,
    required this.fetchedAt,
    this.stale = false,
  });

  /// Copy with only [stale] changed.
  PriceProduct withStale(bool stale) => PriceProduct(
    store: store,
    id: id,
    brand: brand,
    name: name,
    price: price,
    wasPrice: wasPrice,
    offer: offer,
    promos: promos,
    storeUnitPriceText: storeUnitPriceText,
    quantity: quantity,
    inStock: inStock,
    shelf: shelf,
    aisle: aisle,
    dept: dept,
    url: url,
    fetchedAt: fetchedAt,
    stale: stale,
  );

  /// First recognised multi-buy among the promos.
  MultiBuy? get multiBuy {
    for (final p in promos) {
      if (p.multiBuy != null) return p.multiBuy;
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'store': store.value,
    'id': id,
    'brand': brand,
    'name': name,
    'price': price,
    'wasPrice': wasPrice,
    'offer': offer,
    'promos': promos.map((p) => p.toMap()).toList(),
    'storeUnitPriceText': storeUnitPriceText,
    'quantity': quantity?.toMap(),
    'inStock': inStock,
    'shelf': shelf,
    'aisle': aisle,
    'dept': dept,
    'url': url,
    'fetchedAt': Timestamp.fromDate(fetchedAt),
    'stale': stale,
  };

  factory PriceProduct.fromMap(Map<String, dynamic> d) => PriceProduct(
    store: PriceStoreExt.fromString((d['store'] ?? '').toString()),
    id: (d['id'] ?? '').toString(),
    brand: (d['brand'] ?? '').toString(),
    name: (d['name'] ?? '').toString(),
    price: (d['price'] as num?)?.toDouble() ?? 0,
    wasPrice: (d['wasPrice'] as num?)?.toDouble(),
    offer: d['offer'] as String?,
    promos: ((d['promos'] as List?) ?? const [])
        .map((e) => PricePromo.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    storeUnitPriceText: d['storeUnitPriceText'] as String?,
    quantity: d['quantity'] == null
        ? null
        : PackQuantity.fromMap(Map<String, dynamic>.from(d['quantity'] as Map)),
    inStock: d['inStock'] as bool? ?? true,
    shelf: d['shelf'] as String?,
    aisle: d['aisle'] as String?,
    dept: d['dept'] as String?,
    url: d['url'] as String?,
    fetchedAt:
        priceDateFromAny(d['fetchedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    stale: d['stale'] as bool? ?? false,
  );
}
