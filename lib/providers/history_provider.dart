import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/history_entry.dart';
import '../services/items_service.dart';

final historyProvider = StreamProvider.family<List<HistoryEntry>, String>((ref, householdId) {
  if (householdId.isEmpty) return const Stream.empty();
  return ItemsService().historyStream(householdId);
});
