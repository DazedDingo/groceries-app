/// Parses free-text lines like "2 kg chicken" into structured items.
class ParsedTextItem {
  final String name;
  final int quantity;
  final String? unit;

  const ParsedTextItem({required this.name, required this.quantity, this.unit});
}

final _unitAliases = <String, String>{
  'pound': 'lb', 'pounds': 'lb', 'lbs': 'lb',
  'kilo': 'kg', 'kilos': 'kg',
  'gram': 'g', 'grams': 'g',
  'ounce': 'oz', 'ounces': 'oz',
  'litre': 'L', 'litres': 'L', 'liter': 'L', 'liters': 'L', 'l': 'L',
  'cup': 'cups', 'pint': 'pints', 'gallon': 'gallons',
  'bag': 'bags', 'box': 'boxes', 'can': 'cans', 'bottle': 'bottles',
  'pack': 'packs', 'packet': 'packs', 'packets': 'packs',
  'bunch': 'bunches', 'bunches': 'bunches',
  'loaf': 'loaves', 'loaves': 'loaves',
  'doz': 'dozen',
};

const _knownUnits = {
  'g', 'kg', 'ml', 'L', 'oz', 'lb', 'cups', 'pints', 'gallons',
  'packs', 'bags', 'boxes', 'bottles', 'cans', 'dozen', 'loaves', 'bunches',
};

final _unitPattern = RegExp(
  r'^(pounds?|lbs?|kilos?|kg|grams?|g|ounces?|oz|litres?|liters?|l|ml|cups?|pints?|gallons?|bags?|boxes?|cans?|bottles?|packs?|packets?|bunche?s?|loave?s|dozen|doz)\b\s*(?:of\s+)?',
  caseSensitive: false,
);

/// Parse a single line like "2 kg chicken" → ParsedTextItem(name: "chicken", quantity: 2, unit: "kg").
/// Also handles "chicken", "3 chicken", "2 packs chicken".
ParsedTextItem parseTextLine(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const ParsedTextItem(name: '', quantity: 1);

  // Try "N unit name" or "N name"
  final numMatch = RegExp(r'^(\d+)\s+(.+)$').firstMatch(trimmed);
  if (numMatch != null) {
    final qty = int.tryParse(numMatch.group(1)!) ?? 1;
    final rest = numMatch.group(2)!.trim();

    // Try to match a unit after the number
    final unitMatch = _unitPattern.firstMatch(rest);
    if (unitMatch != null) {
      final rawUnit = unitMatch.group(1)!.toLowerCase();
      final unit = _unitAliases[rawUnit] ?? (_knownUnits.contains(rawUnit) ? rawUnit : null);
      final name = rest.substring(unitMatch.end).trim();
      if (name.isNotEmpty) {
        return ParsedTextItem(name: name, quantity: qty, unit: unit);
      }
      // If nothing after unit, the "unit" is actually the item name
      return ParsedTextItem(name: rest, quantity: qty.clamp(1, 99));
    }

    return ParsedTextItem(name: rest, quantity: qty.clamp(1, 99));
  }

  // No leading number — just a name
  return ParsedTextItem(name: trimmed, quantity: 1);
}

/// Parse multiple lines of text into a list of items, skipping blanks.
List<ParsedTextItem> parseTextLines(String text) {
  return text
      .split('\n')
      .map((line) => parseTextLine(line))
      .where((item) => item.name.isNotEmpty)
      .toList();
}
