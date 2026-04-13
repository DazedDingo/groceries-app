import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Auto-redirect if already signed in
    final authState = ref.watch(authStateProvider);
    authState.whenData((user) {
      if (user != null && context.mounted) {
        _redirectAfterAuth(context, user.uid);
      }
    });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Groceries', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 48),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              onPressed: () async {
                try {
                  final cred = await ref.read(authServiceProvider).signInWithGoogle();
                  if (context.mounted && cred.user != null) {
                    await _redirectAfterAuth(context, cred.user!.uid);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign-in failed: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _redirectAfterAuth(BuildContext context, String uid) async {
    final userDoc = await FirebaseFirestore.instance.doc('users/$uid').get();
    final householdId = userDoc.data()?['householdId'] as String?;
    if (!context.mounted) return;
    if (householdId != null && householdId.isNotEmpty) {
      context.go('/list');
    } else {
      context.go('/setup');
    }
  }
}
