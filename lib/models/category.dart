import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class GroceryCategory {
  final String id;
  final String name;
  final Color color;
  final String addedBy;

  const GroceryCategory({required this.id, required this.name, required this.color, required this.addedBy});

  Map<String, dynamic> toMap() => {
    'name': name, 'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'addedBy': addedBy, 'addedAt': FieldValue.serverTimestamp(),
  };

  factory GroceryCategory.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final hex = (d['color'] as String? ?? '#4CAF50').replaceFirst('#', '');
    return GroceryCategory(
      id: doc.id, name: d['name'],
      color: Color(int.parse('FF$hex', radix: 16)),
      addedBy: d['addedBy'] ?? '',
    );
  }
}
