import '../../models/price_product.dart';
import 'auto_match.dart';
import 'price_compare.dart';

/// Pure text helpers for the Compare prices screens.

/// '£1.23', or '-£1.23' for negatives.
String formatPounds(double v) {
  final r = (v * 100).round() / 100;
  return r < 0 ? '-£${(-r).toStringAsFixed(2)}' : '£${r.toStringAsFixed(2)}';
}

/// "3 items" / "1 item".
String itemsLabel(int n) => n == 1 ? '1 item' : '$n items';

/// The first basis (in [CompareBasis] priority order) that [p]'s pack
/// expresses, or null when its size is unknown.
CompareBasis? displayBasis(PriceProduct p) {
  final q = p.quantity;
  if (q == null) return null;
  for (final b in CompareBasis.values) {
    if (amountIn(q, b) != null) return b;
  }
  return null;
}

String _trim(String s) =>
    s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

/// Unit price of [p] on [basis]: weight as £/kg, volume as £/L, count units as
/// 'Np/bag' under £1 or '£x/bag' above. Null when the pack doesn't express the
/// basis.
String? formatUnitCost(PriceProduct p, CompareBasis basis) {
  final u = unitCost(p, basis);
  if (u == null) return null;
  final cost = u * basis.displayFactor;
  final label = basis.perLabel;
  if (basis == CompareBasis.grams || basis == CompareBasis.millilitres) {
    return '£${cost.toStringAsFixed(2)}/$label';
  }
  if (cost < 1) {
    final pence = cost * 100;
    final rounded = pence >= 10
        ? pence.roundToDouble()
        : (pence * 10).roundToDouble() / 10;
    if (rounded < 100) {
      return '${_trim(rounded.toStringAsFixed(1))}p/$label';
    }
    return '£1.00/$label';
  }
  return '£${cost.toStringAsFixed(2)}/$label';
}

/// "£3.99", or "2 × £3.99 = £7.98" when buying several packs.
String formatPackPrice(PriceProduct p, int qty) => qty <= 1
    ? formatPounds(p.price)
    : '$qty × ${formatPounds(p.price)} = ${formatPounds(p.price * qty)}';

/// "Updated just now" / "Updated 5 min ago" / "Updated 2 h ago".
String formatUpdatedAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Updated just now';
  if (d.inMinutes < 60) return 'Updated ${d.inMinutes} min ago';
  return 'Updated ${d.inHours} h ago';
}

/// "saves £14.51 vs 5 × Asda £7.50" for a Costco line that beats Asda, else
/// null.
String? formatCostcoSaving(LineComparison l) {
  final s = l.costcoSaving;
  final a = l.bestAsda;
  if (s == null || a == null || (s * 100).round() <= 0) return null;
  final packs = l.asdaEquivalentPacks ?? 1;
  return 'saves ${formatPounds(s)} vs $packs × Asda ${formatPounds(a.price)}';
}

/// Why a line could not be priced, for the "Couldn't price" section.
String unpricedReason(LineComparison l, AutoMatchResult? auto) {
  if (l.status == LineStatus.unavailable) {
    return 'Marked as not available';
  }
  final parts = <String>['No Asda match'];
  final reason = auto?.costcoRejectReason;
  parts.add(reason == null || reason.isEmpty ? 'no Costco match' : reason);
  return parts.join(' · ');
}

/// Sum of the positive Costco savings across both-store lines.
double grossCostcoSaving(CompareResult r) {
  var sum = 0.0;
  for (final l in r.lines) {
    final s = l.costcoSaving;
    if (s != null && (s * 100).round() > 0) sum += s;
  }
  return sum;
}

class RecommendationText {
  final String headline;

  /// Why, shown under the headline for the Asda-only / forced cases.
  final String? why;
  const RecommendationText(this.headline, this.why);
}

RecommendationText describeRecommendation(CompareResult r, PriceFees fees) {
  final plan = r.splitPlan;
  if (plan.asdaLines.isEmpty && plan.costcoLines.isEmpty) {
    return RecommendationText('Nothing priced yet', r.summary);
  }
  if (r.recommendation == Recommendation.split) {
    return RecommendationText(
      'Order from both',
      r.forcedByCostcoOnly
          ? '${itemsLabel(r.missingAtAsda.length)} only sold at Costco, '
                'so a Costco order is needed anyway.'
          : null,
    );
  }
  final gross = grossCostcoSaving(r);
  final String why;
  if (gross > 0) {
    why =
        'Costco would save only ${formatPounds(gross)}, which does not beat '
        'its ${formatPounds(fees.costcoDelivery)} delivery fee.';
  } else if (r.lines.every((l) => l.bestCostco == null)) {
    why = 'No Costco matches for your list.';
  } else {
    why = 'Costco is not cheaper for anything on your list.';
  }
  return RecommendationText('Just order from Asda', why);
}
