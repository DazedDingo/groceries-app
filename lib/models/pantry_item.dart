import 'package:cloud_firestore/cloud_firestore.dart';

class PantryItem {
  final String id;
  final String name;
  final String categoryId;
  final List<String> preferredStores;
  final int optimalQuantity;
  final int currentQuantity;
  final int? restockAfterDays;
  final int? shelfLifeDays;
  final DateTime? expiresAt;
  final DateTime? lastNudgedAt;
  final DateTime? lastPurchasedAt;

  const PantryItem({
    required this.id, required this.name, required this.categoryId,
    required this.preferredStores, required this.optimalQuantity,
    required this.currentQuantity, required this.restockAfterDays,
    this.shelfLifeDays, this.expiresAt,
    required this.lastNudgedAt, required this.lastPurchasedAt,
  });

  bool get isBelowOptimal => currentQuantity < optimalQuantity;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isExpiringSoon =>
      expiresAt != null &&
      !isExpired &&
      expiresAt!.difference(DateTime.now()).inDays <= 2;

  Map<String, dynamic> toMap() => {
    'name': name, 'categoryId': categoryId,
    'preferredStores': preferredStores,
    'optimalQuantity': optimalQuantity, 'currentQuantity': currentQuantity,
    'restockAfterDays': restockAfterDays,
    'shelfLifeDays': shelfLifeDays,
    'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    'lastNudgedAt': lastNudgedAt != null ? Timestamp.fromDate(lastNudgedAt!) : null,
    'lastPurchasedAt': lastPurchasedAt != null ? Timestamp.fromDate(lastPurchasedAt!) : null,
  };

  factory PantryItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PantryItem(
      id: doc.id, name: d['name'] ?? '',
      categoryId: d['categoryId'] ?? 'uncategorised',
      preferredStores: List<String>.from(d['preferredStores'] ?? []),
      optimalQuantity: d['optimalQuantity'] ?? 1,
      currentQuantity: d['currentQuantity'] ?? 0,
      restockAfterDays: d['restockAfterDays'],
      shelfLifeDays: d['shelfLifeDays'],
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      lastNudgedAt: (d['lastNudgedAt'] as Timestamp?)?.toDate(),
      lastPurchasedAt: (d['lastPurchasedAt'] as Timestamp?)?.toDate(),
    );
  }

  PantryItem copyWith({
    String? name,
    String? categoryId,
    List<String>? preferredStores,
    int? optimalQuantity,
    int? currentQuantity,
    int? restockAfterDays,
    int? shelfLifeDays,
    DateTime? expiresAt,
    DateTime? lastNudgedAt,
    DateTime? lastPurchasedAt,
  }) => PantryItem(
    id: id,
    name: name ?? this.name,
    categoryId: categoryId ?? this.categoryId,
    preferredStores: preferredStores ?? this.preferredStores,
    optimalQuantity: optimalQuantity ?? this.optimalQuantity,
    currentQuantity: currentQuantity ?? this.currentQuantity,
    restockAfterDays: restockAfterDays ?? this.restockAfterDays,
    shelfLifeDays: shelfLifeDays ?? this.shelfLifeDays,
    expiresAt: expiresAt ?? this.expiresAt,
    lastNudgedAt: lastNudgedAt ?? this.lastNudgedAt,
    lastPurchasedAt: lastPurchasedAt ?? this.lastPurchasedAt,
  );
}
