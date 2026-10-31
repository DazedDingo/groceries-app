import 'package:cloud_firestore/cloud_firestore.dart';

import 'price_product.dart';

/// How a link's product lists are used.
/// - [exact]: the user confirmed one specific product per store (only the
///   first entry of each list is used).
/// - [anyOf]: any product in the list is acceptable; the engine picks the
///   cheapest per unit.
enum LinkMode { exact, anyOf }

extension LinkModeExt on LinkMode {
  String get value => switch (this) {
    LinkMode.exact => 'exact',
    LinkMode.anyOf => 'any_of',
  };
  static LinkMode fromString(String s) => switch (s) {
    'any_of' => LinkMode.anyOf,
    _ => LinkMode.exact,
  };
}

/// The remembered match between a shopping-list item and store products.
class PriceLink {
  /// Normalised item name, see [keyFor].
  final String itemKey;
  final LinkMode mode;
  final List<PriceProduct> asda;
  final List<PriceProduct> costco;

  /// The user said this store doesn't sell the item (e.g. fresh milk at
  /// Costco); the engine ignores that store's list.
  final bool asdaUnavailable;
  final bool costcoUnavailable;

  /// True once the user has confirmed or corrected the match; false for
  /// links built by the auto-matcher.
  final bool userConfirmed;
  final DateTime updatedAt;

  const PriceLink({
    required this.itemKey,
    this.mode = LinkMode.exact,
    this.asda = const [],
    this.costco = const [],
    this.asdaUnavailable = false,
    this.costcoUnavailable = false,
    this.userConfirmed = false,
    required this.updatedAt,
  });

  /// Lowercased, trimmed, whitespace-collapsed key for an item name.
  static String keyFor(String itemName) =>
      itemName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Map<String, dynamic> toMap() => {
    'itemKey': itemKey,
    'mode': mode.value,
    'asda': asda.map((p) => p.toMap()).toList(),
    'costco': costco.map((p) => p.toMap()).toList(),
    'asdaUnavailable': asdaUnavailable,
    'costcoUnavailable': costcoUnavailable,
    'userConfirmed': userConfirmed,
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  static List<PriceProduct> _products(dynamic v) => ((v as List?) ?? const [])
      .map((e) => PriceProduct.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();

  factory PriceLink.fromMap(Map<String, dynamic> d) => PriceLink(
    itemKey: (d['itemKey'] ?? '').toString(),
    mode: LinkModeExt.fromString((d['mode'] ?? '').toString()),
    asda: _products(d['asda']),
    costco: _products(d['costco']),
    asdaUnavailable: d['asdaUnavailable'] as bool? ?? false,
    costcoUnavailable: d['costcoUnavailable'] as bool? ?? false,
    userConfirmed: d['userConfirmed'] as bool? ?? false,
    updatedAt:
        priceDateFromAny(d['updatedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
