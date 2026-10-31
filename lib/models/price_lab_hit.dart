/// One product/price candidate found by the Price lab extractor.
class PriceLabHit {
  const PriceLabHit({
    this.name,
    this.price,
    this.priceText,
    this.unitPriceText,
    this.promoText,
    this.url,
    this.raw,
    this.source,
  });

  final String? name;
  final double? price;
  final String? priceText;
  final String? unitPriceText;
  final String? promoText;
  final String? url;
  final String? raw;

  /// 'jsonld' or 'dom'.
  final String? source;

  /// Tolerant of missing / wrongly-typed fields. The JS side emits `price`
  /// either as a string ("£1.25", "85p", "1.25") or a number.
  factory PriceLabHit.fromJson(Map<String, dynamic> json) {
    String? str(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final priceText = str(json['priceText'] ?? json['price']);
    return PriceLabHit(
      name: str(json['name']),
      price: parsePriceText(priceText),
      priceText: priceText,
      unitPriceText: str(json['unitPrice'] ?? json['unitPriceText']),
      promoText: str(json['promo'] ?? json['promoText']),
      url: str(json['url']),
      raw: str(json['raw']),
      source: str(json['source']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'priceText': priceText,
        'unitPrice': unitPriceText,
        'promo': promoText,
        'url': url,
        'raw': raw,
        'source': source,
      };

  /// Parses a list of hit maps, skipping entries that aren't maps.
  static List<PriceLabHit> listFromJson(dynamic list) {
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map) PriceLabHit.fromJson(Map<String, dynamic>.from(e)),
    ];
  }
}

final _poundRe = RegExp(r'£\s*(\d[\d,]*(?:\.\d+)?)');
final _penceRe = RegExp(r'(?<![\d.])(\d+)\s*p\b', caseSensitive: false);
final _plainRe = RegExp(r'^\s*(\d[\d,]*(?:\.\d+)?)\s*$');

/// "£1.25" -> 1.25, "85p" -> 0.85, "£1" -> 1.0, "1.25" -> 1.25.
/// Returns null for null / empty / unparseable input.
double? parsePriceText(String? text) {
  if (text == null) return null;
  final pound = _poundRe.firstMatch(text);
  if (pound != null) {
    return double.tryParse(pound.group(1)!.replaceAll(',', ''));
  }
  final pence = _penceRe.firstMatch(text);
  if (pence != null) {
    final p = int.tryParse(pence.group(1)!);
    return p == null ? null : p / 100;
  }
  final plain = _plainRe.firstMatch(text);
  if (plain != null) {
    return double.tryParse(plain.group(1)!.replaceAll(',', ''));
  }
  return null;
}
