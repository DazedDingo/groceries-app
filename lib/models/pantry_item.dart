import 'package:cloud_firestore/cloud_firestore.dart';

/// Where in the kitchen this item lives. String values are persisted in
/// Firestore so they are stable across clients — do not rename without a
/// migration. Null = unknown.
enum PantryLocation {
  fridge('fridge', 'Fridge'),
  freezer('freezer', 'Freezer'),
  pantry('pantry', 'Pantry'),
  counter('counter', 'Counter'),
  other('other', 'Other');

  final String id;
  final String label;
  const PantryLocation(this.id, this.label);

  static PantryLocation? fromId(String? id) {
    if (id == null) return null;
    for (final loc in PantryLocation.values) {
      if (loc.id == id) return loc;
    }
    return null;
  }
}

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
  final PantryLocation? location;
  final bool isHighPriority;

  const PantryItem({
    required this.id, required this.name, required this.categoryId,
    required this.preferredStores, required this.optimalQuantity,
    required this.currentQuantity, required this.restockAfterDays,
    this.shelfLifeDays, this.expiresAt,
    required this.lastNudgedAt, required this.lastPurchasedAt,
    this.location,
    this.isHighPriority = false,
  });

  bool get isBelowOptimal => currentQuantity < optimalQuantity;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isExpiringSoon =>
      expiresAt != null &&
      !isExpired &&
      expiresAt!.difference(DateTime.now()).inDays <= 2;

  /// Item has been sitting untouched for a while — a soft "still there?" nudge,
  /// independent of hard expiry. Fires when we have stock on hand but haven't
  /// repurchased in ~60 days and the item isn't already flagged as expired or
  /// expiring soon.
  bool get isStale {
    if (currentQuantity <= 0) return false;
    if (isExpired || isExpiringSoon) return false;
    final purchased = lastPurchasedAt;
    if (purchased == null) return false;
    return DateTime.now().difference(purchased).inDays >= 60;
  }

  Map<String, dynamic> toMap() => {
    'name': name, 'categoryId': categoryId,
    'preferredStores': preferredStores,
    'optimalQuantity': optimalQuantity, 'currentQuantity': currentQuantity,
    'restockAfterDays': restockAfterDays,
    'shelfLifeDays': shelfLifeDays,
    'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    'lastNudgedAt': lastNudgedAt != null ? Timestamp.fromDate(lastNudgedAt!) : null,
    'lastPurchasedAt': lastPurchasedAt != null ? Timestamp.fromDate(lastPurchasedAt!) : null,
    'location': location?.id,
    'isHighPriority': isHighPriority,
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
      location: PantryLocation.fromId(d['location'] as String?),
      isHighPriority: d['isHighPriority'] ?? false,
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
    PantryLocation? location,
    bool? isHighPriority,
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
    location: location ?? this.location,
    isHighPriority: isHighPriority ?? this.isHighPriority,
  );
}
