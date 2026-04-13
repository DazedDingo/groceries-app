import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const _defaultStores = [
  {'name': 'Tesco', 'trolleySlug': 'tesco'},
  {'name': 'Asda', 'trolleySlug': 'asda'},
  {'name': "Sainsbury's", 'trolleySlug': 'sainsburys'},
  {'name': 'Morrisons', 'trolleySlug': 'morrisons'},
  {'name': 'Waitrose', 'trolleySlug': 'waitrose'},
  {'name': 'Aldi', 'trolleySlug': 'aldi'},
  {'name': 'Lidl', 'trolleySlug': 'lidl'},
  {'name': 'Ocado', 'trolleySlug': 'ocado'},
];

const _defaultCategories = [
  {'name': 'Meats', 'color': '#EF5350'},
  {'name': 'Dairy', 'color': '#42A5F5'},
  {'name': 'Produce', 'color': '#66BB6A'},
  {'name': 'Spices', 'color': '#FFA726'},
  {'name': 'Frozen', 'color': '#29B6F6'},
  {'name': 'Bakery', 'color': '#8D6E63'},
  {'name': 'Drinks', 'color': '#AB47BC'},
  {'name': 'Household', 'color': '#78909C'},
  {'name': 'Uncategorised', 'color': '#546E7A'},
];

class HouseholdService {
  final FirebaseFirestore _db;
  HouseholdService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  String _randomToken(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<String> createHousehold(User user, String name) async {
    final inviteToken = _randomToken(32);
    final webhookToken = _randomToken(32);
    final ref = await _db.collection('households').add({
      'name': name,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'inviteToken': inviteToken,
    });

    // Write member first so isMember() is true when rules evaluate the batch below.
    await _db.doc('households/${ref.id}/members/${user.uid}').set({
      'uid': user.uid,
      'displayName': user.displayName ?? 'User',
      'email': user.email,
      'joinedAt': FieldValue.serverTimestamp(),
      'webhookToken': webhookToken,
      'fcmToken': null,
    });

    // Store householdId on the user doc for fast, permission-safe lookup.
    await _db.doc('users/${user.uid}').set({'householdId': ref.id}, SetOptions(merge: true));

    // Write invite token to public lookup collection.
    await _db.doc('invites/$inviteToken').set({'householdId': ref.id});

    final batch = _db.batch();
    for (final s in _defaultStores) {
      final storeRef = _db.collection('households/${ref.id}/stores').doc();
      batch.set(storeRef, {...s, 'addedBy': user.uid, 'addedAt': FieldValue.serverTimestamp()});
    }

    for (final c in _defaultCategories) {
      final catRef = _db.collection('households/${ref.id}/categories').doc();
      batch.set(catRef, {...c, 'addedBy': user.uid, 'addedAt': FieldValue.serverTimestamp()});
    }

    await batch.commit();
    return ref.id;
  }

  Future<String?> joinByInviteToken(User user, String token) async {
    final inviteDoc = await _db.doc('invites/$token').get();
    if (!inviteDoc.exists) return null;

    final householdId = inviteDoc.data()!['householdId'] as String;
    final webhookToken = _randomToken(32);
    await _db.doc('households/$householdId/members/${user.uid}').set({
      'uid': user.uid,
      'displayName': user.displayName ?? 'User',
      'email': user.email,
      'joinedAt': FieldValue.serverTimestamp(),
      'webhookToken': webhookToken,
      'fcmToken': null,
    });
    await _db.doc('users/${user.uid}').set({'householdId': householdId}, SetOptions(merge: true));
    return householdId;
  }

  Future<String?> getHouseholdIdForUser(String uid) async {
    final doc = await _db.doc('users/$uid').get();
    return doc.data()?['householdId'] as String?;
  }
}
