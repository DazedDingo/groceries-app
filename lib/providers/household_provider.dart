import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/household_service.dart';
import 'auth_provider.dart';

final householdServiceProvider = Provider<HouseholdService>((ref) => HouseholdService());

final householdIdProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ref.read(householdServiceProvider).getHouseholdIdForUser(user.uid);
});
