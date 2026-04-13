import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/history_provider.dart';
import '../../providers/household_provider.dart';
import '../../models/history_entry.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final history = ref.watch(historyProvider(householdId));

    return Scaffold(
      appBar: AppBar(title: const Text('Item History')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('No history yet.'));
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              return ListTile(
                leading: _ActionIcon(e.action),
                title: Text(e.itemName),
                subtitle: Text(e.byName),
                trailing: Text(
                  _formatDate(e.at),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ActionIcon extends StatelessWidget {
  final HistoryAction action;
  const _ActionIcon(this.action);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (action) {
      HistoryAction.added => Icon(Icons.add_circle_outline, color: scheme.primary),
      HistoryAction.bought => const Icon(Icons.check_circle_outline, color: Colors.green),
      HistoryAction.deleted => Icon(Icons.remove_circle_outline, color: scheme.error),
    };
  }
}
