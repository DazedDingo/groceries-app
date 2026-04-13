import 'package:cloud_firestore/cloud_firestore.dart';

class PantryItem {
  final String id;
  final String name;
  final String categoryId;
  final List<String> preferredStores;
  final int optimalQuantity;
  final int currentQuantity;
  final int? restockAfterDays;
  final DateTime? lastNudgedAt;
  final DateTime? lastPurchasedAt;

  const PantryItem({
    required this.id, required this.name, required this.categoryId,
    required this.preferredStores, required this.optimalQuantity,
    required this.currentQuantity, required this.restockAfterDays,
    required this.lastNudgedAt, required this.lastPurchasedAt,
  });

  bool get isBelowOptimal => currentQuantity < optimalQuantity;

  Map<String, dynamic> toMap() => {
    'name': name, 'categoryId': categoryId,
    'preferredStores': preferredStores,
    'optimalQuantity': optimalQuantity, 'currentQuantity': currentQuantity,
    'restockAfterDays': restockAfterDays,
    'lastNudgedAt': lastNudgedAt != null ? Timestamp.fromDate(lastNudgedAt!) : null,
    'lastPurchasedAt': lastPurchasedAt != null ? Timestamp.fromDate(lastPurchasedAt!) : null,
  };

  factory PantryItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PantryItem(
      id: doc.id, name: d['name'],
      categoryId: d['categoryId'] ?? 'uncategorised',
      preferredStores: List<String>.from(d['preferredStores'] ?? []),
      optimalQuantity: d['optimalQuantity'] ?? 1,
      currentQuantity: d['currentQuantity'] ?? 0,
      restockAfterDays: d['restockAfterDays'],
      lastNudgedAt: (d['lastNudgedAt'] as Timestamp?)?.toDate(),
      lastPurchasedAt: (d['lastPurchasedAt'] as Timestamp?)?.toDate(),
    );
  }

  PantryItem copyWith({int? currentQuantity, DateTime? lastPurchasedAt}) => PantryItem(
    id: id, name: name, categoryId: categoryId, preferredStores: preferredStores,
    optimalQuantity: optimalQuantity,
    currentQuantity: currentQuantity ?? this.currentQuantity,
    restockAfterDays: restockAfterDays, lastNudgedAt: lastNudgedAt,
    lastPurchasedAt: lastPurchasedAt ?? this.lastPurchasedAt,
  );
}
