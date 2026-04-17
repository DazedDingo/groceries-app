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

// Desaturated, value-spaced palette tuned to the refined sage theme.
// Categories are rendered as small (r=6) circle avatars and as low-alpha
// chip fills (~0.3), so AA text contrast isn't the gating concern — visual
// distinctness and palette harmony are. Hues are spread around the wheel;
// saturation kept low so they sit next to the sage primary without clashing.
// Hex values chosen so no two categories share a hue bucket.
const _defaultCategories = [
  {'name': 'Meats', 'color': '#C46B5B'},     // muted terracotta
  {'name': 'Dairy', 'color': '#7E9CB8'},     // dusty sky
  {'name': 'Produce', 'color': '#8CB07E'},   // sage-adjacent
  {'name': 'Spices', 'color': '#D69D5B'},    // muted ochre
  {'name': 'Frozen', 'color': '#8FC3C6'},    // soft teal
  {'name': 'Bakery', 'color': '#A08972'},    // warm taupe
  {'name': 'Drinks', 'color': '#9F7FB2'},    // dusty plum
  {'name': 'Household', 'color': '#7B8B96'}, // slate blue-grey
  {'name': 'Uncategorised', 'color': '#8A8E8F'}, // neutral
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
