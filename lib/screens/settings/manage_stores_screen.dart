import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/stores_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/auth_provider.dart';

class ManageStoresScreen extends ConsumerWidget {
  const ManageStoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores = ref.watch(storesProvider).value ?? [];
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final uid = ref.watch(authStateProvider).value?.uid ?? '';
    final service = ref.watch(storesServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Stores')),
      body: ListView.builder(
        itemCount: stores.length,
        itemBuilder: (_, i) {
          final store = stores[i];
          return ListTile(
            title: Text(store.name),
            subtitle: store.trolleySlug != null
                ? const Text('Price data available')
                : const Text('No price data'),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => service.removeStore(householdId, store.id),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ctrl = TextEditingController();
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Add custom store'),
              content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Store name')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () { service.addStore(householdId, ctrl.text.trim(), uid); Navigator.pop(context); },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
