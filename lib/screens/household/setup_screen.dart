import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/household_provider.dart';
import '../shared/pantry_background.dart';

class SetupScreen extends ConsumerStatefulWidget {
  final String? inviteToken;
  const SetupScreen({super.key, this.inviteToken});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _nameController = TextEditingController();
  late final TextEditingController _tokenController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.inviteToken ?? '');
    // Auto-join if opened via deep link with a valid token
    final token = widget.inviteToken;
    if (token != null && RegExp(r'^[a-zA-Z0-9]{20,64}$').hasMatch(token)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
  }

  Future<void> _create() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await ref.read(householdServiceProvider).createHousehold(user, _nameController.text.trim());
      if (mounted) context.go('/list');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final id = await ref.read(householdServiceProvider).joinByInviteToken(user, _tokenController.text.trim());
      if (id == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite token not found')));
      } else if (mounted) {
        context.go('/list');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up household'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: PantryBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 2,
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  Text(
                    'A household is a shared space for your grocery list, pantry, and recipes. Pick one option:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Text('Create a new household',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    "Start fresh — you'll be the first member. Other people can join later using an invite link you share from Settings.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Household name',
                      hintText: 'e.g. The Smiths',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _create, child: const Text('Create household')),
                  const Divider(height: 48),
                  Text('Join an existing household',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Someone already in the household can send you an invite link. Opening it here fills in the token automatically — or paste one manually below.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Invite token',
                      hintText: 'Paste from invite link',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _join, child: const Text('Join household')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
