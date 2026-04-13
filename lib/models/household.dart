import 'package:cloud_firestore/cloud_firestore.dart';

class Household {
  final String id;
  final String name;
  final String createdBy;
  final String inviteToken;

  const Household({required this.id, required this.name, required this.createdBy, required this.inviteToken});

  factory Household.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Household(id: doc.id, name: d['name'], createdBy: d['createdBy'], inviteToken: d['inviteToken']);
  }
}
