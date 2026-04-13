import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart';

/// Global deep link token extracted on cold start or from stream.
String? pendingInviteToken;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Check if app was opened via deep link (cold start)
  final appLinks = AppLinks();
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null && initialUri.host == 'join') {
    pendingInviteToken = initialUri.queryParameters['token'];
  }

  runApp(const ProviderScope(child: GroceriesApp()));
}
