import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../services/notification_service.dart';
import '../../services/unit_converter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final user = ref.watch(authStateProvider).value;
    final notifService = ref.watch(notificationServiceProvider);
    final householdName = ref.watch(householdNameProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // --- Profile & Household ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null
                      ? Text(
                          (user?.displayName ?? '?')[0].toUpperCase(),
                          style: Theme.of(context).textTheme.titleLarge,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'Unknown',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (householdName.isNotEmpty)
                        Text(
                          householdName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

          // --- Preferences ---
          SwitchListTile(
            title: const Text('Use US units'),
            subtitle: Text(ref.watch(unitSystemProvider) == UnitSystem.us
                ? 'oz, lb, fl oz, gal'
                : 'g, kg, ml, L'),
            value: ref.watch(unitSystemProvider) == UnitSystem.us,
            onChanged: (_) => ref.read(unitSystemProvider.notifier).toggle(),
          ),
          ListTile(
            title: const Text('Manage Categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/categories'),
          ),
          const Divider(),

          // --- Household ---
          ListTile(
            title: const Text('Share invite code'),
            subtitle: const Text('Share this code so others can join your household'),
            onTap: () async {
              try {
                final doc = await FirebaseFirestore.instance.doc('households/$householdId').get();
                final token = doc.data()?['inviteToken'] as String?;
                if (token != null) {
                  // Ensure invite lookup doc exists (self-healing for older households)
                  final inviteRef = FirebaseFirestore.instance.doc('invites/$token');
                  final inviteDoc = await inviteRef.get();
                  if (!inviteDoc.exists) {
                    await inviteRef.set({'householdId': householdId});
                  }
                  await Share.share(
                    'Join my grocery household!\n\n'
                    'Tap this link: groceries://join?token=$token\n\n'
                    'Or enter this code manually: $token',
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.wallet),
            title: const Text('Open Google Wallet'),
            subtitle: const Text('Quick access to store loyalty cards'),
            onTap: () async {
              const intent = AndroidIntent(
                action: 'android.intent.action.MAIN',
                package: 'com.google.android.apps.walletnfcrel',
                componentName: 'com.google.android.apps.walletnfcrel.MainActivity',
              );
              try {
                await intent.launch();
              } catch (_) {
                // App not installed — open Play Store listing
                final playStore = Uri.parse('market://details?id=com.google.android.apps.walletnfcrel');
                try {
                  await launchUrl(playStore, mode: LaunchMode.externalApplication);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open Google Wallet')),
                    );
                  }
                }
              }
            },
          ),
          const Divider(),

          // --- Advanced ---
          ExpansionTile(
            title: const Text('Advanced'),
            children: [
              ListTile(
                title: const Text('Copy IFTTT webhook URL'),
                subtitle: const Text('Use this in your IFTTT Google Assistant applet'),
                onTap: () async {
                  final token = await notifService.getWebhookToken(householdId, user?.uid ?? '');
                  if (token != null) {
                    await Clipboard.setData(ClipboardData(
                      text: 'https://us-central1-gorceries-app-8c24e.cloudfunctions.net/addItemWebhook/$token',
                    ));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Webhook URL copied')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                title: const Text('Rotate webhook token'),
                subtitle: const Text('Invalidates your current IFTTT applet URL'),
                onTap: () => notifService.rotateWebhookToken(householdId, user?.uid ?? ''),
              ),
            ],
          ),
          const Divider(),
          ListTile(
            title: const Text('Sign out'),
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
