import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'household_provider.dart';

class WebhookStatus {
  final DateTime? lastWebhookAt;
  final String? lastItemName;
  final int? lastQuantity;

  const WebhookStatus({
    this.lastWebhookAt,
    this.lastItemName,
    this.lastQuantity,
  });

  factory WebhookStatus.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const WebhookStatus();
    return WebhookStatus(
      lastWebhookAt: (map['lastWebhookAt'] as Timestamp?)?.toDate(),
      lastItemName: map['lastItemName'] as String?,
      lastQuantity: map['lastQuantity'] as int?,
    );
  }
}

/// Streams the webhookStatus doc written by the IFTTT handler after each
/// successful trigger. Returns an empty status when the doc hasn't been
/// written yet (i.e., the webhook has never fired for this household).
final webhookStatusProvider = StreamProvider<WebhookStatus>((ref) async* {
  final householdId = await ref.watch(householdIdProvider.future);
  if (householdId == null || householdId.isEmpty) {
    yield const WebhookStatus();
    return;
  }
  yield* FirebaseFirestore.instance
      .doc('households/$householdId/config/webhookStatus')
      .snapshots()
      .map((snap) => WebhookStatus.fromMap(snap.data()));
});
