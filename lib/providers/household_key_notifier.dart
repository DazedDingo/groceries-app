import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/household_config_service.dart';
import 'household_provider.dart';

final householdConfigServiceProvider = Provider<HouseholdConfigService>(
  (ref) => HouseholdConfigService(),
);

/// Backs a per-household API key by subscribing to Firestore. On first use,
/// migrates any value previously stored in SharedPreferences (under
/// [legacyPrefsKey]) up into Firestore so users don't lose the key they
/// already entered.
class HouseholdKeyNotifier extends StateNotifier<String> {
  final Ref _ref;
  final String firestoreField;
  final String legacyPrefsKey;

  StreamSubscription<Map<String, String>>? _sub;
  String? _householdId;
  bool _migrationChecked = false;

  HouseholdKeyNotifier(
    this._ref, {
    required this.firestoreField,
    required this.legacyPrefsKey,
  }) : super('') {
    _init();
  }

  Future<void> _init() async {
    _householdId = await _ref.read(householdIdProvider.future);
    if (_householdId == null) return;
    final svc = _ref.read(householdConfigServiceProvider);
    _sub = svc.apiKeysStream(_householdId!).listen((keys) {
      final remoteKey = keys[firestoreField] ?? '';
      if (remoteKey.isNotEmpty) {
        if (state != remoteKey) state = remoteKey;
      } else if (!_migrationChecked) {
        _migrationChecked = true;
        _maybeMigrate();
      }
    });
  }

  Future<void> _maybeMigrate() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyPrefsKey) ?? '';
    if (legacy.isEmpty || _householdId == null) return;
    final svc = _ref.read(householdConfigServiceProvider);
    await svc.setKey(_householdId!, firestoreField, legacy);
    // Clean up the local copy now that Firestore is the source of truth.
    await prefs.remove(legacyPrefsKey);
  }

  Future<void> set(String value) async {
    final v = value.trim();
    state = v;
    _householdId ??= await _ref.read(householdIdProvider.future);
    if (_householdId == null) return;
    final svc = _ref.read(householdConfigServiceProvider);
    await svc.setKey(_householdId!, firestoreField, v);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
