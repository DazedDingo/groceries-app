import '../../models/price_link.dart';
import '../../models/price_product.dart';
import 'promo_parser.dart';

/// What two packs are compared per. Declaration order is the priority order
/// used by [chooseBasis] (specific count units first, then weight, volume,
/// generic count).
enum CompareBasis {
  wash,
  bag,
  roll,
  tablet,
  pod,
  capsule,
  sheet,
  grams,
  millilitres,
  count,
}

extension CompareBasisExt on CompareBasis {
  /// Short label for "per ..." text. Weight and volume are per kg / L in the
  /// UI even though amounts are held in g / ml.
  String get perLabel => switch (this) {
    CompareBasis.grams => 'kg',
    CompareBasis.millilitres => 'L',
    CompareBasis.count => 'unit',
    _ => name,
  };

  /// Multiplier from the per-amount cost (per g / per ml) to the displayed
  /// per-[perLabel] cost.
  double get displayFactor => switch (this) {
    CompareBasis.grams || CompareBasis.millilitres => 1000,
    _ => 1,
  };

  /// The countUnit this basis matches, or null for weight/volume/generic.
  String? get countUnit => switch (this) {
    CompareBasis.wash ||
    CompareBasis.bag ||
    CompareBasis.roll ||
    CompareBasis.tablet ||
    CompareBasis.pod ||
    CompareBasis.capsule ||
    CompareBasis.sheet => name,
    _ => null,
  };
}

class PriceFees {
  final double asdaDelivery;
  final double costcoDelivery;
  const PriceFees({this.asdaDelivery = 6.0, this.costcoDelivery = 5.99});
}

enum LineStatus { unlinked, asdaOnly, costcoOnly, both, unavailable }

enum Recommendation { asdaOnly, split }

/// Basis shared by [a] and [b], or null. Preference: a shared specific
/// countUnit, then grams, then millilitres, then a generic count (both have
/// counts and the units are equal or one side is plain 'each').
CompareBasis? chooseBasis(PackQuantity? a, PackQuantity? b) {
  if (a == null || b == null) return null;
  final au = a.countUnit;
  final bu = b.countUnit;
  if (a.count != null && b.count != null && au != null && au == bu) {
    for (final basis in CompareBasis.values) {
      if (basis.countUnit == au) return basis;
    }
  }
  if (a.grams != null && b.grams != null) return CompareBasis.grams;
  if (a.millilitres != null && b.millilitres != null) {
    return CompareBasis.millilitres;
  }
  if (a.count != null && b.count != null) {
    final aGeneric = au == null || au == 'each';
    final bGeneric = bu == null || bu == 'each';
    if (au == bu || aGeneric || bGeneric) return CompareBasis.count;
  }
  return null;
}

/// Amount of [basis] in pack [q] (grams, ml or count), or null when the pack
/// doesn't express it. A generic-count basis accepts any count.
double? amountIn(PackQuantity q, CompareBasis basis) {
  final double? v;
  switch (basis) {
    case CompareBasis.grams:
      v = q.grams;
    case CompareBasis.millilitres:
      v = q.millilitres;
    case CompareBasis.count:
      v = q.count;
    default:
      v = q.countUnit == basis.countUnit ? q.count : null;
  }
  return (v == null || v <= 0) ? null : v;
}

/// Pack price divided by the amount of [basis] in it (per g, per ml or per
/// unit), or null when the amount is unknown.
double? unitCost(PriceProduct p, CompareBasis basis) {
  final q = p.quantity;
  if (q == null) return null;
  final amount = amountIn(q, basis);
  return amount == null ? null : p.price / amount;
}

class CompareLine {
  final String itemName;

  /// Packs wanted. At Asda this is Asda packs; for the Costco comparison it is
  /// Costco packs (see [LineComparison.costcoSaving]).
  final int qty;
  final PriceLink? link;
  const CompareLine({required this.itemName, this.qty = 1, this.link});
}

class LineComparison {
  final CompareLine line;
  final LineStatus status;
  final PriceProduct? bestAsda;
  final PriceProduct? bestCostco;
  final CompareBasis? basis;

  /// Per g / ml / unit (see [CompareBasisExt.displayFactor]) at list price.
  final double? asdaUnitCost;
  final double? costcoUnitCost;

  /// Asda unit cost over the equivalent quantity including multi-buys.
  final double? asdaEffectiveUnitCost;

  /// Null when there's no basis, a store is missing, or it's a tie.
  final PriceStore? cheaperStore;

  /// Equivalent Asda packs for [CompareLine.qty] Costco packs.
  final int? asdaEquivalentPacks;

  /// Asda cost of those equivalent packs (multi-buys applied).
  final double? asdaEquivalentCost;

  /// Asda cost of [CompareLine.qty] Asda packs (multi-buys applied).
  final double? asdaCost;

  /// Costco price x qty.
  final double? costcoCost;

  /// asdaEquivalentCost - costcoCost. Positive means Costco is cheaper. Null
  /// when there's no basis or a store is missing.
  final double? costcoSaving;

  const LineComparison({
    required this.line,
    required this.status,
    this.bestAsda,
    this.bestCostco,
    this.basis,
    this.asdaUnitCost,
    this.costcoUnitCost,
    this.asdaEffectiveUnitCost,
    this.cheaperStore,
    this.asdaEquivalentPacks,
    this.asdaEquivalentCost,
    this.asdaCost,
    this.costcoCost,
    this.costcoSaving,
  });
}

class SplitPlan {
  /// Lines bought at Costco: those with a positive saving, plus Costco-only
  /// lines.
  final List<LineComparison> costcoLines;
  final List<LineComparison> asdaLines;
  final double asdaSpend;
  final double costcoSpend;
  final double asdaFee;
  final double costcoFee;
  double get fees => asdaFee + costcoFee;
  double get total => asdaSpend + costcoSpend + fees;
  const SplitPlan({
    required this.costcoLines,
    required this.asdaLines,
    required this.asdaSpend,
    required this.costcoSpend,
    required this.asdaFee,
    required this.costcoFee,
  });
}

class CompareResult {
  final List<LineComparison> lines;
  final int unlinkedCount;
  final int unavailableCount;

  /// Items from Asda (Asda packs x qty, multi-buys applied) + Asda delivery.
  /// Costco-only lines are not included; see [missingAtAsda].
  final double asdaOnlyTotal;
  final double asdaOnlyItems;

  /// Costco-only lines: the user can't get these at Asda.
  final List<LineComparison> missingAtAsda;
  final SplitPlan splitPlan;

  /// Sum of the moved lines' savings minus Costco delivery. Savings compare
  /// the Costco packs with the equivalent Asda amount, so this is not
  /// asdaOnlyTotal - splitPlan.total when bulk buying changes quantities.
  final double splitNetSaving;
  final Recommendation recommendation;

  /// True when the split is recommended because Costco-only lines force a
  /// Costco order, not because of savings.
  final bool forcedByCostcoOnly;
  final String summary;

  const CompareResult({
    required this.lines,
    required this.unlinkedCount,
    required this.unavailableCount,
    required this.asdaOnlyTotal,
    required this.asdaOnlyItems,
    required this.missingAtAsda,
    required this.splitPlan,
    required this.splitNetSaving,
    required this.recommendation,
    required this.forcedByCostcoOnly,
    required this.summary,
  });
}

double _r2(double v) => (v * 100).round() / 100;

String _pounds(double v) {
  final r = _r2(v);
  return r < 0 ? '-£${(-r).toStringAsFixed(2)}' : '£${r.toStringAsFixed(2)}';
}

String _items(int n) => n == 1 ? '1 item' : '$n items';

/// Products the engine may use for one store, honouring [LinkMode] and the
/// unavailable flag. In-stock products are preferred: out-of-stock ones are
/// only used when nothing is in stock.
List<PriceProduct> _candidates(
  PriceLink link,
  List<PriceProduct> products,
  bool unavailable,
) {
  if (unavailable || products.isEmpty) return const [];
  final acceptable = link.mode == LinkMode.exact
      ? [products.first]
      : List<PriceProduct>.of(products);
  final inStock = acceptable.where((p) => p.inStock).toList();
  return inStock.isNotEmpty ? inStock : acceptable;
}

// Cost per unit used to rank Asda candidates. When [qty] packs would trigger
// the product's multi-buy, it is the multi-buy-effective cost of those packs
// per unit; otherwise the list-price unit cost.
double? _rankCost(PriceProduct p, CompareBasis basis, int qty, bool multiBuys) {
  final u = unitCost(p, basis);
  if (u == null || !multiBuys) return u;
  final mb = p.multiBuy;
  if (mb == null || qty < mb.quantity) return u;
  final amount = amountIn(p.quantity!, basis)!;
  return effectiveCost(p.price, qty, mb) / (qty * amount);
}

// Lowest cost first; ties go to the cheaper pack, then the earlier entry in
// the link's list (the sort is stable, so list order is the last tie-break).
// With [multiBuys] (Asda), a candidate whose multi-buy applies to [qty] packs
// is ranked by its multi-buy-effective unit cost.
PriceProduct? _cheapest(
  List<PriceProduct> c,
  CompareBasis basis, {
  int qty = 1,
  bool multiBuys = false,
}) {
  final scored = <(PriceProduct, double)>[];
  for (final p in c) {
    final u = _rankCost(p, basis, qty, multiBuys);
    if (u != null) scored.add((p, u));
  }
  if (scored.isEmpty) return null;
  var best = scored.first;
  for (final s in scored.skip(1)) {
    if (s.$2 < best.$2 - 1e-12 ||
        ((s.$2 - best.$2).abs() <= 1e-12 && s.$1.price < best.$1.price)) {
      best = s;
    }
  }
  return best.$1;
}

PriceProduct _lowestPrice(List<PriceProduct> c) {
  var best = c.first;
  for (final p in c.skip(1)) {
    if (p.price < best.price) best = p;
  }
  return best;
}

// Best product from one store alone: the highest-priority basis that every
// candidate expresses, else the lowest pack price.
PriceProduct _bestOfOneStore(
  List<PriceProduct> c, {
  int qty = 1,
  bool multiBuys = false,
}) {
  for (final basis in CompareBasis.values) {
    if (c.every(
      (p) => p.quantity != null && amountIn(p.quantity!, basis) != null,
    )) {
      return _cheapest(c, basis, qty: qty, multiBuys: multiBuys)!;
    }
  }
  return _lowestPrice(c);
}

/// Compares one list line. Selection rules:
///  1. Candidates per store: exact links use only the first product; anyOf
///     links use all. In-stock candidates beat out-of-stock ones.
///  2. If both stores have candidates, the basis is the highest-priority
///     [CompareBasis] that some Asda/Costco pair shares ([chooseBasis]).
///  3. On that basis each store picks its lowest list-price unit cost; ties go
///     to the cheaper pack, then to the earlier entry in the link's list.
///     At Asda, when [CompareLine.qty] reaches a product's multi-buy
///     quantity, that product is ranked by its multi-buy-effective unit cost
///     (so "2 for £1.80" can beat a cheaper-looking single). Below the
///     multi-buy quantity, and always at Costco, list price decides.
///  4. With no shared basis each store picks its lowest pack price and
///     cheaperStore / costcoSaving stay null.
LineComparison compareLine(CompareLine line) {
  final link = line.link;
  if (link == null) {
    return LineComparison(line: line, status: LineStatus.unlinked);
  }
  final asdaC = _candidates(link, link.asda, link.asdaUnavailable);
  final costcoC = _candidates(link, link.costco, link.costcoUnavailable);

  if (asdaC.isEmpty && costcoC.isEmpty) {
    final touched =
        link.asda.isNotEmpty ||
        link.costco.isNotEmpty ||
        link.asdaUnavailable ||
        link.costcoUnavailable;
    return LineComparison(
      line: line,
      status: touched ? LineStatus.unavailable : LineStatus.unlinked,
    );
  }
  if (costcoC.isEmpty) {
    final best = _bestOfOneStore(asdaC, qty: line.qty, multiBuys: true);
    return LineComparison(
      line: line,
      status: LineStatus.asdaOnly,
      bestAsda: best,
      asdaCost: effectiveCost(best.price, line.qty, best.multiBuy),
    );
  }
  if (asdaC.isEmpty) {
    final best = _bestOfOneStore(costcoC);
    return LineComparison(
      line: line,
      status: LineStatus.costcoOnly,
      bestCostco: best,
      costcoCost: best.price * line.qty,
    );
  }

  // Both stores: find the best shared basis across all pairs.
  CompareBasis? basis;
  for (final a in asdaC) {
    for (final c in costcoC) {
      final b = chooseBasis(a.quantity, c.quantity);
      if (b != null && (basis == null || b.index < basis.index)) basis = b;
    }
  }

  PriceProduct? bestA;
  PriceProduct? bestC;
  if (basis != null) {
    bestA = _cheapest(asdaC, basis, qty: line.qty, multiBuys: true);
    bestC = _cheapest(costcoC, basis);
  }
  if (basis == null || bestA == null || bestC == null) {
    bestA = _lowestPrice(asdaC);
    bestC = _lowestPrice(costcoC);
    return LineComparison(
      line: line,
      status: LineStatus.both,
      bestAsda: bestA,
      bestCostco: bestC,
      asdaCost: effectiveCost(bestA.price, line.qty, bestA.multiBuy),
      costcoCost: bestC.price * line.qty,
    );
  }

  final aAmount = amountIn(bestA.quantity!, basis)!;
  final cAmount = amountIn(bestC.quantity!, basis)!;
  final equivPacks = ((cAmount * line.qty / aAmount) - 1e-9).ceil().clamp(
    1,
    1 << 30,
  );
  final asdaEquivCost = effectiveCost(bestA.price, equivPacks, bestA.multiBuy);
  final costcoCost = bestC.price * line.qty;
  final saving = asdaEquivCost - costcoCost;
  final r = _r2(saving);
  return LineComparison(
    line: line,
    status: LineStatus.both,
    bestAsda: bestA,
    bestCostco: bestC,
    basis: basis,
    asdaUnitCost: bestA.price / aAmount,
    costcoUnitCost: bestC.price / cAmount,
    asdaEffectiveUnitCost: asdaEquivCost / (equivPacks * aAmount),
    cheaperStore: r > 0 ? PriceStore.costco : (r < 0 ? PriceStore.asda : null),
    asdaEquivalentPacks: equivPacks,
    asdaEquivalentCost: asdaEquivCost,
    asdaCost: effectiveCost(bestA.price, line.qty, bestA.multiBuy),
    costcoCost: costcoCost,
    costcoSaving: saving,
  );
}

/// Compares a whole basket and decides whether to split the order.
///
/// Unlinked and unavailable lines are excluded from every total (and counted).
/// Costco-only lines can't be bought at Asda: they are listed in
/// [CompareResult.missingAtAsda], force a Costco order, and once that order
/// exists any both-store line with a positive saving also moves. Without
/// Costco-only lines, a split is recommended only when the summed savings of
/// the lines with a positive saving exceed the Costco delivery fee.
CompareResult compareBasket(
  List<CompareLine> input, {
  PriceFees fees = const PriceFees(),
}) {
  final lines = input.map(compareLine).toList();
  final unlinked = lines.where((l) => l.status == LineStatus.unlinked).length;
  final unavailable = lines
      .where((l) => l.status == LineStatus.unavailable)
      .length;

  final asdaCapable = lines.where(
    (l) => l.status == LineStatus.asdaOnly || l.status == LineStatus.both,
  );
  final costcoOnly = lines
      .where((l) => l.status == LineStatus.costcoOnly)
      .toList();

  final asdaItems = asdaCapable.fold<double>(0, (s, l) => s + l.asdaCost!);
  final asdaOnlyTotal = asdaCapable.isEmpty
      ? 0.0
      : asdaItems + fees.asdaDelivery;

  final saverLines = lines
      .where(
        (l) => l.status == LineStatus.both && (_r2(l.costcoSaving ?? 0)) > 0,
      )
      .toList();
  final grossSaving = saverLines.fold<double>(0, (s, l) => s + l.costcoSaving!);
  final anyMoved = saverLines.isNotEmpty || costcoOnly.isNotEmpty;
  final net = _r2(grossSaving - (anyMoved ? fees.costcoDelivery : 0));

  final forced = costcoOnly.isNotEmpty;
  final split = forced || net > 0;

  final moved = split
      ? <LineComparison>[...saverLines, ...costcoOnly]
      : <LineComparison>[];
  final stays = asdaCapable.where((l) => !moved.contains(l)).toList();
  final asdaSpend = stays.fold<double>(0, (s, l) => s + l.asdaCost!);
  final costcoSpend = moved.fold<double>(0, (s, l) => s + l.costcoCost!);
  final plan = SplitPlan(
    costcoLines: moved,
    asdaLines: stays,
    asdaSpend: asdaSpend,
    costcoSpend: costcoSpend,
    asdaFee: stays.isEmpty ? 0 : fees.asdaDelivery,
    costcoFee: moved.isEmpty ? 0 : fees.costcoDelivery,
  );

  final String summary;
  if (asdaCapable.isEmpty && costcoOnly.isEmpty) {
    summary = 'Nothing to compare yet.';
  } else if (!split) {
    summary = saverLines.isEmpty
        ? 'Order everything from Asda.'
        : 'Costco would save ${_pounds(grossSaving)} on '
              '${_items(saverLines.length)}, but that does not beat the '
              '${_pounds(fees.costcoDelivery)} delivery. '
              'Order everything from Asda.';
  } else if (forced) {
    summary =
        'Order ${_items(moved.length)} from Costco '
        '(${costcoOnly.length} not available at Asda): '
        'saves ${_pounds(grossSaving)}, minus '
        '${_pounds(fees.costcoDelivery)} delivery = ${_pounds(net)}';
  } else {
    summary =
        'Order ${_items(moved.length)} from Costco: '
        'saves ${_pounds(grossSaving)}, minus '
        '${_pounds(fees.costcoDelivery)} delivery = ${_pounds(net)}';
  }

  return CompareResult(
    lines: lines,
    unlinkedCount: unlinked,
    unavailableCount: unavailable,
    asdaOnlyTotal: asdaOnlyTotal,
    asdaOnlyItems: asdaItems,
    missingAtAsda: costcoOnly,
    splitPlan: plan,
    splitNetSaving: net,
    recommendation: split ? Recommendation.split : Recommendation.asdaOnly,
    forcedByCostcoOnly: forced,
    summary: summary,
  );
}
