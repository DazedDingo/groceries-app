import 'package:cloud_firestore/cloud_firestore.dart';

class TemplateItem {
  final String name;
  final int quantity;
  final String? unit;
  final String categoryId;

  const TemplateItem({
    required this.name,
    this.quantity = 1,
    this.unit,
    required this.categoryId,
  });

  Map<String, dynamic> toMap() => {
    'name': name, 'quantity': quantity, 'unit': unit, 'categoryId': categoryId,
  };

  factory TemplateItem.fromMap(Map<String, dynamic> m) => TemplateItem(
    name: m['name'] ?? '',
    quantity: m['quantity'] ?? 1,
    unit: m['unit'],
    categoryId: m['categoryId'] ?? 'uncategorised',
  );
}

class ShoppingTemplate {
  final String id;
  final String name;
  final List<TemplateItem> items;
  final DateTime createdAt;

  const ShoppingTemplate({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'items': items.map((i) => i.toMap()).toList(),
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory ShoppingTemplate.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ShoppingTemplate(
      id: doc.id,
      name: d['name'] ?? '',
      items: (d['items'] as List<dynamic>?)
          ?.map((i) => TemplateItem.fromMap(i as Map<String, dynamic>))
          .toList() ?? [],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
