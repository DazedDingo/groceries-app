import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/providers/webhook_status_provider.dart';

void main() {
  group('WebhookStatus.fromMap', () {
    test('null map returns empty status', () {
      final s = WebhookStatus.fromMap(null);
      expect(s.lastWebhookAt, isNull);
      expect(s.lastItemName, isNull);
      expect(s.lastQuantity, isNull);
    });

    test('empty map returns empty status', () {
      final s = WebhookStatus.fromMap(const {});
      expect(s.lastWebhookAt, isNull);
      expect(s.lastItemName, isNull);
      expect(s.lastQuantity, isNull);
    });

    test('parses all fields', () async {
      final fs = FakeFirebaseFirestore();
      await fs.doc('x/y').set({
        'lastWebhookAt': Timestamp.fromDate(DateTime(2026, 4, 17, 10)),
        'lastItemName': 'milk',
        'lastQuantity': 2,
      });
      final snap = await fs.doc('x/y').get();
      final s = WebhookStatus.fromMap(snap.data());
      expect(s.lastWebhookAt, DateTime(2026, 4, 17, 10));
      expect(s.lastItemName, 'milk');
      expect(s.lastQuantity, 2);
    });

    test('tolerates missing optional fields', () async {
      final fs = FakeFirebaseFirestore();
      await fs.doc('x/y').set({
        'lastWebhookAt': Timestamp.fromDate(DateTime(2026, 4, 17, 10)),
      });
      final snap = await fs.doc('x/y').get();
      final s = WebhookStatus.fromMap(snap.data());
      expect(s.lastWebhookAt, DateTime(2026, 4, 17, 10));
      expect(s.lastItemName, isNull);
      expect(s.lastQuantity, isNull);
    });
  });
}
