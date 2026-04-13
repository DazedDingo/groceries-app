import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db;
  NotificationService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Future<void> init(String householdId, String uid, GlobalKey<NavigatorState> navigatorKey) async {
    await _fcm.requestPermission();
    final token = await _fcm.getToken();
    if (token != null) {
      await _db.doc('households/$householdId/members/$uid').update({'fcmToken': token});
    }

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final pantryItemId = message.data['pantryItemId'];
      if (pantryItemId != null) {
        navigatorKey.currentContext?.go('/pantry/$pantryItemId');
      }
    });
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
