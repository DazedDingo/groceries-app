import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/household_service.dart';
import 'auth_provider.dart';

final householdServiceProvider = Provider<HouseholdService>((ref) => HouseholdService());

final householdIdProvider = FutureProvider<String?>((ref) async {
  // Watch the auth stream so we re-run when the user actually changes, but
  // fall back to FirebaseAuth.currentUser during transient AsyncLoading
  // (e.g., token refresh) so we don't briefly resolve to null and collapse
  // every downstream list/stream to empty.
  final authAsync = ref.watch(authStateProvider);
  final user = authAsync.valueOrNull ?? FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return ref.read(householdServiceProvider).getHouseholdIdForUser(user.uid);
});

final householdNameProvider = FutureProvider<String?>((ref) async {
  final householdId = await ref.watch(householdIdProvider.future);
  if (householdId == null) return null;
  final doc = await FirebaseFirestore.instance.doc('households/$householdId').get();
  return doc.data()?['name'] as String?;
});
