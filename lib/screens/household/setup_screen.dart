import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/household_provider.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _nameController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = false;

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
      appBar: AppBar(title: const Text('Set up household')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Household name')),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _create, child: const Text('Create household')),
                  const Divider(height: 48),
                  TextField(controller: _tokenController, decoration: const InputDecoration(labelText: 'Invite token')),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: _join, child: const Text('Join household')),
                ],
              ),
            ),
    );
  }
}
