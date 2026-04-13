import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/templates_service.dart';
import '../models/shopping_template.dart';
import 'household_provider.dart';

final templatesServiceProvider = Provider<TemplatesService>((ref) => TemplatesService());

final templatesProvider = StreamProvider<List<ShoppingTemplate>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(templatesServiceProvider).templatesStream(householdId);
});
