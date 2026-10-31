/// Multi-buy promotions ("Any 2 for £1.20", "3 for 2") and the maths to price
/// a basket quantity against them. Pure Dart.
class MultiBuy {
  /// Number of items in one deal group.
  final int quantity;

  /// Fixed price for one group ("2 for £5" -> 5.0). Null for "N for M" deals,
  /// where the group costs [payFor] x the unit price.
  final double? total;

  /// "3 for 2" -> 2. Null for fixed-price deals.
  final int? payFor;

  const MultiBuy(this.quantity, double this.total) : payFor = null;

  /// "N for M": buy [quantity], pay for [payFor] at the unit price.
  const MultiBuy.nForM(this.quantity, int this.payFor) : total = null;

  /// Price of one full group given the single-item [unitPrice].
  double groupPrice(double unitPrice) => total ?? payFor! * unitPrice;

  @override
  bool operator ==(Object other) =>
      other is MultiBuy &&
      other.quantity == quantity &&
      other.total == total &&
      other.payFor == payFor;

  @override
  int get hashCode => Object.hash(quantity, total, payFor);

  @override
  String toString() => total != null
      ? 'MultiBuy($quantity for £${total!.toStringAsFixed(2)})'
      : 'MultiBuy($quantity for $payFor)';
}

final RegExp _multiBuyRe = RegExp(
  r'^\s*(?:any|buy)?\s*(\d+)\s*for\s*(£)?\s*(\d+(?:\.\d+)?)\s*(p)?(?![\d.])',
  caseSensitive: false,
);

/// Parses a promo name into a [MultiBuy]. Returns null for anything we don't
/// understand (the caller keeps the name for display).
///
/// Handles "Any 2 for £1.20", "2 for £5", "Any 5 for £5", "2 for 90p" and
/// "3 for 2" (pay for 2, get 3).
MultiBuy? parseMultiBuy(String name) {
  final m = _multiBuyRe.firstMatch(name);
  if (m == null) return null;
  final qty = int.parse(m.group(1)!);
  if (qty < 2) return null;
  final value = double.parse(m.group(3)!);
  final hasPound = m.group(2) != null;
  final hasPence = m.group(4) != null;
  if (hasPound && hasPence) return null;
  if (hasPound) return MultiBuy(qty, value);
  if (hasPence) return MultiBuy(qty, value / 100);
  // Bare "3 for 2": the second number is a count of paid-for items.
  if (value != value.roundToDouble()) return null;
  final payFor = value.round();
  if (payFor < 1 || payFor >= qty) return null;
  return MultiBuy.nForM(qty, payFor);
}

/// Cost of buying [qty] items at [unitPrice], using as many full multi-buy
/// groups as fit at the deal price and the remainder at [unitPrice]. A deal
/// that would cost more than buying singly is ignored.
double effectiveCost(double unitPrice, int qty, MultiBuy? mb) {
  if (qty <= 0) return 0;
  if (mb == null || mb.quantity < 2) return unitPrice * qty;
  final groups = qty ~/ mb.quantity;
  final rest = qty % mb.quantity;
  final groupCost = mb.groupPrice(unitPrice);
  final perGroup = groupCost < unitPrice * mb.quantity
      ? groupCost
      : unitPrice * mb.quantity;
  return groups * perGroup + rest * unitPrice;
}
