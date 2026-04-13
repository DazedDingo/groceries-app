import 'package:cloud_firestore/cloud_firestore.dart';

enum HistoryAction { added, bought, deleted }

extension HistoryActionExt on HistoryAction {
  String get value => switch (this) {
    HistoryAction.added => 'added',
    HistoryAction.bought => 'bought',
    HistoryAction.deleted => 'deleted',
  };
  static HistoryAction fromString(String s) => switch (s) {
    'bought' => HistoryAction.bought,
    'deleted' => HistoryAction.deleted,
    _ => HistoryAction.added,
  };
}

class HistoryEntry {
  final String id;
  final String itemName;
  final String categoryId;
  final HistoryAction action;
  final int quantity;
  final DateTime at;
  final String byName;

  const HistoryEntry({
    required this.id, required this.itemName, required this.categoryId,
    required this.action, required this.quantity, required this.at,
    required this.byName,
  });

  factory HistoryEntry.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return HistoryEntry(
      id: doc.id,
      itemName: d['itemName'] ?? '',
      categoryId: d['categoryId'] ?? 'uncategorised',
      action: HistoryActionExt.fromString(d['action'] ?? 'added'),
      quantity: d['quantity'] ?? 1,
      at: (d['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      byName: d['byName'] ?? 'Unknown',
    );
  }

  static Map<String, dynamic> toMap({
    required String itemName, required String categoryId,
    required HistoryAction action, required int quantity, required String byName,
  }) => {
    'itemName': itemName, 'categoryId': categoryId,
    'action': action.value, 'quantity': quantity,
    'at': FieldValue.serverTimestamp(), 'byName': byName,
  };
}
