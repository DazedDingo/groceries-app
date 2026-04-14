import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/recipe_search_provider.dart';
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
                category: 'android.intent.category.LAUNCHER',
                package: 'com.google.android.apps.walletnfcrel',
                flags: <int>[0x10000000],
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

          // --- Recipe sources ---
          ExpansionTile(
            title: const Text('Recipe sources'),
            subtitle: const Text('Discover recipes online'),
            children: [
              const ListTile(
                leading: Icon(Icons.public),
                title: Text('TheMealDB'),
                subtitle: Text('Free, no setup needed'),
                trailing: Icon(Icons.check, color: Colors.green),
              ),
              _SpoonacularKeyTile(),
            ],
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
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report an issue'),
            subtitle: const Text('File a bug or idea on GitHub'),
            onTap: () => context.go('/settings/report-issue'),
          ),
          const Divider(),
          const _AboutTile(),
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

class _SpoonacularKeyTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SpoonacularKeyTile> createState() => _SpoonacularKeyTileState();
}

class _SpoonacularKeyTileState extends ConsumerState<_SpoonacularKeyTile> {
  bool _editing = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(spoonacularKeyProvider);
    final hasKey = key.isNotEmpty;

    if (_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Spoonacular API key',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Powers recipe search on the Discover tab. Free tier allows 150 requests/day — plenty for a household.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to get a key',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  const Text('1. Go to spoonacular.com/food-api and click "Start Now".'),
                  const Text('2. Sign up for a free account (email + password).'),
                  const Text('3. After signing in, open the Profile menu → "Show/Hide API Key".'),
                  const Text('4. Copy the key and paste it below.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://spoonacular.com/food-api'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open spoonacular.com/food-api'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Paste API key',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _editing = false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await ref
                          .read(spoonacularKeyProvider.notifier)
                          .set(_ctrl.text);
                      if (!mounted) return;
                      setState(() => _editing = false);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return ListTile(
      leading: const Icon(Icons.restaurant),
      title: const Text('Spoonacular'),
      subtitle: Text(hasKey ? 'Key saved' : 'Tap to add your free API key'),
      trailing: hasKey
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove key',
              onPressed: () =>
                  ref.read(spoonacularKeyProvider.notifier).set(''),
            )
          : const Icon(Icons.chevron_right),
      onTap: () {
        _ctrl.text = key;
        setState(() => _editing = true);
      },
    );
  }
}

class _AboutTile extends StatefulWidget {
  const _AboutTile();

  @override
  State<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends State<_AboutTile> {
  String _versionLine = 'Loading…';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _versionLine = 'v${info.version} (build ${info.buildNumber})';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('About'),
      subtitle: Text('Groceries — $_versionLine · by DazedDingo'),
      onTap: () => showAboutDialog(
        context: context,
        applicationName: 'Groceries',
        applicationVersion: _versionLine,
        applicationLegalese:
            'A household grocery + pantry + recipe companion.\n\nAuthored by DazedDingo.',
      ),
    );
  }
}
