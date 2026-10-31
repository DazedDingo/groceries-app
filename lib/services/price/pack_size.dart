import '../../models/price_product.dart';

const double _mlPerPint = 568.261;

const String _unitAlt = r'kg|g|ml|cl|l|litres?|liters?|ltr|pints?';
const String _countWordAlt =
    r'washe?s?|bags?|rolls?|tablets?|tabs?|pacs?|pods?|capsules?|sheets?|'
    r'servings?|wipes?|count|packs?|pk|pcs|pieces?|each';

// "6 x 250g", "4x125g", "6X1L", "40 x 14g".
final RegExp _multiUnitRe = RegExp(
  r'(?<![\d.])(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*(' + _unitAlt + r')\b',
);
// "2 x 100 Pack", "10 x 56 wipes", "3 x 3 Pack".
final RegExp _multiCountRe = RegExp(
  r'(?<![\d.])(\d+)\s*x\s*(\d+)\b(?:\s*(' + _countWordAlt + r')\b)?',
);
// "x 12"
final RegExp _xCountRe = RegExp(r'(?<![a-z0-9])x\s*(\d+)\b');
// "(560g)", "(2.565L)", "(1.431 L)"
final RegExp _parenTotalRe = RegExp(
  r'\(\s*(\d+(?:\.\d+)?)\s*(' + _unitAlt + r')\s*\)',
);
final RegExp _plainUnitRe = RegExp(
  r'(?<![\d.])(\d+(?:\.\d+)?)\s*(' + _unitAlt + r')\b',
);
// "160 Tea Bags", "8PK", "4 Durable Kitchen Towels Rolls" (up to 3 words
// between the number and the count word).
final RegExp _countRe = RegExp(
  r'(?<![\d.])(\d+)(?:\s*|\s+(?:[a-z][a-z-]*\s+){1,3}?)(' +
      _countWordAlt +
      r')\b',
);

final RegExp _tabletWordRe = RegExp(r'\b(tablets?|tabs?|pacs?)\b');
final RegExp _teaBagRe = RegExp(r'tea\s*bags?');
final RegExp _dishwasherRe = RegExp(r'dishwasher');
final RegExp _rollContextRe = RegExp(
  r'toilet\s+(tissue|roll|paper)|kitchen\s+(roll|towel)|\btowels?\b|\brolls?\b',
);

class _Parsed {
  double? grams;
  double? ml;
  double? count;

  /// Normalised singular count unit, or null when only a generic word
  /// (pack / count / pk) was seen.
  String? unit;
}

double _round3(double v) => (v * 1000).round() / 1000;

/// Converts a number + unit string into (isMass, amountInBaseUnit).
({bool mass, double amount}) _toBase(double n, String unit) {
  switch (unit) {
    case 'kg':
      return (mass: true, amount: n * 1000);
    case 'g':
      return (mass: true, amount: n);
    case 'ml':
      return (mass: false, amount: n);
    case 'cl':
      return (mass: false, amount: n * 10);
    case 'l':
    case 'ltr':
    case 'litre':
    case 'litres':
    case 'liter':
    case 'liters':
      return (mass: false, amount: n * 1000);
    default: // pint(s)
      return (mass: false, amount: n * _mlPerPint);
  }
}

void _setWeightVol(_Parsed p, double n, String unit) {
  final b = _toBase(n, unit);
  if (b.mass) {
    p.grams = _round3(b.amount);
  } else {
    p.ml = _round3(b.amount);
  }
}

/// Normalises a matched count word to the singular unit, or null for the
/// generic words (pack / count / pk / pcs / each).
String? _normaliseCountWord(String w) {
  if (w.startsWith('wash')) return 'wash';
  if (w.startsWith('bag')) return 'bag';
  if (w.startsWith('roll')) return 'roll';
  if (w.startsWith('tablet') || w.startsWith('tab') || w.startsWith('pac')) {
    // "pack(s)" starts with "pac" too; it is generic.
    if (w.startsWith('pack')) return null;
    return 'tablet';
  }
  if (w.startsWith('pod')) return 'pod';
  if (w.startsWith('capsule')) return 'capsule';
  if (w.startsWith('sheet')) return 'sheet';
  if (w.startsWith('serving')) return 'serving';
  if (w.startsWith('wipe')) return 'wipe';
  return null;
}

_Parsed _parseText(String raw) {
  final p = _Parsed();
  var s = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // Bracketed total, e.g. "(560g)", "(2.565L)". Wins over computed totals.
  double? parenGrams;
  double? parenMl;
  final paren = _parenTotalRe.firstMatch(s);
  if (paren != null) {
    final tmp = _Parsed();
    _setWeightVol(tmp, double.parse(paren.group(1)!), paren.group(2)!);
    parenGrams = tmp.grams;
    parenMl = tmp.ml;
  }
  // Drop all bracketed text ("(157 Sheets)" is per-roll detail, not a count).
  s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  // "1 Cup Tea Bags" is a product descriptor, not a count of 1.
  s = s.replaceAll(RegExp(r'\b1 cup\b'), ' ');

  // Multipacks with a unit: "24 x 415g".
  final mu = _multiUnitRe.firstMatch(s);
  if (mu != null) {
    final n = double.parse(mu.group(1)!);
    final each = double.parse(mu.group(2)!);
    final tmp = _Parsed();
    _setWeightVol(tmp, n * each, mu.group(3)!);
    p.grams = tmp.grams;
    p.ml = tmp.ml;
    // Tablets sold as "40 x 14g": N is the number of tablets.
    if (_tabletWordRe.hasMatch(s)) {
      p.count = n;
      p.unit = 'tablet';
    }
    s = s.replaceRange(mu.start, mu.end, ' ');
  }

  // Multipacks without a unit: "2 x 100 Pack".
  if (p.count == null) {
    final mc = _multiCountRe.firstMatch(s);
    if (mc != null) {
      p.count = double.parse(mc.group(1)!) * double.parse(mc.group(2)!);
      final w = mc.group(3);
      p.unit = w == null ? null : _normaliseCountWord(w);
      s = s.replaceRange(mc.start, mc.end, ' ');
    } else {
      final xc = _xCountRe.firstMatch(s);
      if (xc != null) {
        p.count = double.parse(xc.group(1)!);
        s = s.replaceRange(xc.start, xc.end, ' ');
      }
    }
  }

  // Plain weight / volume.
  if (p.grams == null && p.ml == null) {
    final pm = _plainUnitRe.firstMatch(s);
    if (pm != null) {
      _setWeightVol(p, double.parse(pm.group(1)!), pm.group(2)!);
    }
  }
  if (parenGrams != null) p.grams = parenGrams;
  if (parenMl != null) p.ml = parenMl;

  // Counts.
  if (p.count == null) {
    final cm = _countRe.firstMatch(s);
    if (cm != null) {
      p.count = double.parse(cm.group(1)!);
      p.unit = _normaliseCountWord(cm.group(2)!);
    }
  }
  return p;
}

_Parsed _parseField(String field) {
  final f = field.trim().toLowerCase();
  final r = RegExp(r'^(\d+)\s*r$').firstMatch(f); // Asda "12R" = 12 rolls
  if (r != null) {
    return _Parsed()
      ..count = double.parse(r.group(1)!)
      ..unit = 'roll';
  }
  return _parseText(f);
}

String _inferUnit(String context) {
  if (_teaBagRe.hasMatch(context)) return 'bag';
  if (_rollContextRe.hasMatch(context)) return 'roll';
  return 'each';
}

/// Parses a pack quantity from a product [text] (name) and, for Asda, the
/// structured PACK_SIZE field.
///
/// PACK_SIZE wins for weight/volume when it provides one; the name supplies
/// counts (washes, bags, rolls, tablets...). Generic counts ("24 Pack",
/// "115 Count") take their unit from context (tea bags -> bag, toilet tissue
/// -> roll, dishwasher -> tablet) and fall back to 'each'. Returns null when
/// nothing parses.
PackQuantity? parsePackQuantity(String text, {String? packSizeField}) {
  final name = _parseText(text);
  final field = (packSizeField == null || packSizeField.trim().isEmpty)
      ? null
      : _parseField(packSizeField);

  double? grams;
  double? ml;
  if (field != null && (field.grams != null || field.ml != null)) {
    grams = field.grams;
    ml = field.ml;
  } else {
    grams = name.grams;
    ml = name.ml;
  }

  double? count;
  String? unit;
  if (name.count != null) {
    count = name.count;
    unit = name.unit;
  } else if (field?.count != null) {
    count = field!.count;
    unit = field.unit;
  }

  if (grams == null && ml == null && count == null) return null;

  String? countUnit;
  if (count != null) {
    final context = '${text.toLowerCase()} ${packSizeField ?? ''}';
    countUnit = unit ?? _inferUnit(context);
    // Dishwasher products are sold as tablets / pacs / capsules / pods:
    // treat them as one unit so brands compare.
    if (_dishwasherRe.hasMatch(context) &&
        const {'each', 'capsule', 'pod', 'tablet'}.contains(countUnit)) {
      countUnit = 'tablet';
    }
  }
  return PackQuantity(
    grams: grams,
    millilitres: ml,
    count: count,
    countUnit: countUnit,
  );
}
