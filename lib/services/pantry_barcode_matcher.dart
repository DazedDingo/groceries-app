import '../models/pantry_item.dart';
import 'fuzzy_match.dart';

class PantryBarcodeMatch {
  final PantryItem? exact;
  final List<PantryItem> fuzzy;
  const PantryBarcodeMatch({this.exact, this.fuzzy = const []});

  bool get hasMatch => exact != null || fuzzy.isNotEmpty;
}

PantryBarcodeMatch findPantryMatch(String scannedName, List<PantryItem> pantry) {
  final scanned = scannedName.trim().toLowerCase();
  if (scanned.isEmpty) return const PantryBarcodeMatch();
  PantryItem? exact;
  final fuzzy = <PantryItem>[];
  for (final p in pantry) {
    final pn = p.name.trim().toLowerCase();
    if (pn.isEmpty) continue;
    if (pn == scanned) {
      exact = p;
      continue;
    }
    if (isFuzzyMatch(scanned, pn)) fuzzy.add(p);
  }
  return PantryBarcodeMatch(exact: exact, fuzzy: fuzzy);
}
