import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  final FirebaseMessaging _fcm;
  final FirebaseFirestore _db;
  NotificationService({FirebaseFirestore? db, FirebaseMessaging? fcm})
      : _db = db ?? FirebaseFirestore.instance,
        _fcm = fcm ?? FirebaseMessaging.instance;

  /// Requests notification permission (no-op once granted) and persists the
  /// current FCM token under the caller's member doc so cloud functions can
  /// push to every device registered to the household.
  Future<void> registerToken(String householdId, String uid) async {
    await _fcm.requestPermission();
    final token = await _fcm.getToken();
    if (token != null) {
      await _db
          .doc('households/$householdId/members/$uid')
          .update({'fcmToken': token});
    }
  }

  Future<String?> getWebhookToken(String householdId, String uid) async {
    final doc = await _db.doc('households/$householdId/members/$uid').get();
    return doc.data()?['webhookToken'] as String?;
  }

  Future<void> rotateWebhookToken(String householdId, String uid) async {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    final token = List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
    await _db.doc('households/$householdId/members/$uid').update({'webhookToken': token});
  }
}
