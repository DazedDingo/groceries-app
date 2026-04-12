import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../services/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final user = ref.watch(authStateProvider).value;
    final notifService = ref.watch(notificationServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Manage Categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/categories'),
          ),
          ListTile(
            title: const Text('Manage Stores'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/stores'),
          ),
          const Divider(),
          ListTile(
            title: const Text('Share invite link'),
            onTap: () => Share.share('Join my grocery household: groceries://join/$householdId'),
          ),
          ListTile(
            leading: const Icon(Icons.wallet),
            title: const Text('Open Google Wallet'),
            subtitle: const Text('Quick access to store loyalty cards'),
            onTap: () async {
              final uri = Uri.parse('https://wallet.google.com');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open Google Wallet')),
                );
              }
            },
          ),
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
