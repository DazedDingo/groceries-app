import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/price_link.dart';
import 'price_compare.dart';

/// Storage for the price comparison feature, all under
/// `households/{hid}/config/`:
///
/// - `priceLinks`: `{links: {itemKey: PriceLink.toMap()}}`, ONLY links the
///   user confirmed (auto-matches are recomputed every run).
/// - `priceSettings`: `{asdaDelivery, costcoDelivery}`.
///
/// Never touches any other config doc (apiKeys etc. live beside these).
class PriceLinksService {
  final FirebaseFirestore _db;
  PriceLinksService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _linksDoc(String hid) =>
      _db.doc('households/$hid/config/priceLinks');

  DocumentReference<Map<String, dynamic>> _settingsDoc(String hid) =>
      _db.doc('households/$hid/config/priceSettings');

  Stream<Map<String, PriceLink>> linksStream(String householdId) {
    return _linksDoc(householdId).snapshots().map((doc) {
      final raw = doc.data()?['links'];
      final out = <String, PriceLink>{};
      if (raw is! Map) return out;
      raw.forEach((key, value) {
        if (value is! Map) return;
        try {
          final link = PriceLink.fromMap(Map<String, dynamic>.from(value));
          out[key.toString()] = link;
        } catch (_) {
          // Skip a malformed entry rather than lose every link.
        }
      });
      return out;
    });
  }

  /// Saves [link] as user-confirmed. Only this item's entry is written, so
  /// concurrent edits of different items never clobber each other.
  Future<void> saveLink(String householdId, PriceLink link) async {
    if (link.itemKey.isEmpty) {
      throw ArgumentError.value(
        link.itemKey,
        'link.itemKey',
        'must not be empty',
      );
    }
    final confirmed = PriceLink(
      itemKey: link.itemKey,
      mode: link.mode,
      asda: link.asda,
      costco: link.costco,
      asdaUnavailable: link.asdaUnavailable,
      costcoUnavailable: link.costcoUnavailable,
      userConfirmed: true,
      updatedAt: link.updatedAt,
    );
    // Nested-map merge: deep-merges, replacing just links.<key> (and the key
    // is a map key, so dots or slashes in item names are safe).
    await _linksDoc(householdId).set({
      'links': {link.itemKey: confirmed.toMap()},
    }, SetOptions(merge: true));
  }

  /// Removes one item's link; a no-op when the doc or key doesn't exist.
  Future<void> removeLink(String householdId, String itemKey) async {
    final ref = _linksDoc(householdId);
    try {
      await ref.update({
        FieldPath(['links', itemKey]): FieldValue.delete(),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }

  Stream<PriceFees> settingsStream(String householdId) {
    return _settingsDoc(householdId).snapshots().map((doc) {
      final d = doc.data();
      const defaults = PriceFees();
      return PriceFees(
        asdaDelivery:
            (d?['asdaDelivery'] as num?)?.toDouble() ?? defaults.asdaDelivery,
        costcoDelivery:
            (d?['costcoDelivery'] as num?)?.toDouble() ??
            defaults.costcoDelivery,
      );
    });
  }

  Future<void> saveSettings(String householdId, PriceFees fees) async {
    await _settingsDoc(householdId).set({
      'asdaDelivery': fees.asdaDelivery,
      'costcoDelivery': fees.costcoDelivery,
    }, SetOptions(merge: true));
  }
}
