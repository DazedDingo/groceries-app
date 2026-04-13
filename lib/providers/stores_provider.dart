import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/stores_service.dart';
import '../models/store.dart';
import 'household_provider.dart';

final storesServiceProvider = Provider<StoresService>((ref) => StoresService());

final storesProvider = StreamProvider<List<Store>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return const Stream.empty();
  return ref.watch(storesServiceProvider).storesStream(householdId);
});
