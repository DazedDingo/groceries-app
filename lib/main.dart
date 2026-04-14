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

  // Replace the default release-mode silent white rectangle with a visible
  // error card so build-time exceptions never present as "a blank screen".
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Something went wrong rendering this screen',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: Colors.red)),
                ]),
                const SizedBox(height: 12),
                Text(details.exceptionAsString(),
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  // Check if app was opened via deep link (cold start)
  final appLinks = AppLinks();
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null && initialUri.host == 'join') {
    pendingInviteToken = initialUri.queryParameters['token'];
  }

  runApp(const ProviderScope(child: GroceriesApp()));
}
