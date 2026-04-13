import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/templates_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/categories_provider.dart';
import '../../models/shopping_template.dart';
import '../../models/item.dart';
import '../../services/category_guesser.dart';
import '../shared/empty_state.dart';
import '../shared/list_skeleton.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    final householdId = ref.watch(householdIdProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Shopping Templates')),
      body: templates.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.list_alt,
              title: 'No templates yet',
              subtitle: 'Save your weekly staples as a template to quickly add them to your list',
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final t = list[i];
              return ListTile(
                title: Text(t.name),
                subtitle: Text('${t.items.length} items'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_shopping_cart),
                      tooltip: 'Add all to list',
                      onPressed: () => _addTemplateToList(context, ref, t, householdId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete template',
                      onPressed: () => _deleteTemplate(context, ref, t, householdId),
                    ),
                  ],
                ),
                onTap: () => _showTemplateItems(context, t),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref, householdId),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showTemplateItems(BuildContext context, ShoppingTemplate template) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template.name, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...template.items.map((item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              trailing: Text(
                item.unit != null ? '${item.quantity} ${item.unit}' : '${item.quantity}',
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _addTemplateToList(
    BuildContext context,
    WidgetRef ref,
    ShoppingTemplate template,
    String householdId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add "${template.name}"?'),
        content: Text('This will add ${template.items.length} items to your shopping list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add all')),
        ],
      ),
    );
    if (confirm != true) return;

    final user = ref.read(authStateProvider).valueOrNull;
    final addedBy = AddedBy(
      uid: user?.uid,
      displayName: user?.displayName ?? 'Unknown',
      source: ItemSource.app,
    );

    try {
      for (final item in template.items) {
        await ref.read(itemsServiceProvider).addItem(
          householdId: householdId,
          name: item.name,
          categoryId: item.categoryId,
          preferredStores: [],
          pantryItemId: null,
          quantity: item.quantity,
          unit: item.unit,
          addedBy: addedBy,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${template.items.length} items from "${template.name}"')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add items: $e')),
        );
      }
    }
  }

  Future<void> _deleteTemplate(
    BuildContext context,
    WidgetRef ref,
    ShoppingTemplate template,
    String householdId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${template.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(templatesServiceProvider).deleteTemplate(
        householdId: householdId,
        templateId: template.id,
      );
    }
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, String householdId) {
    final nameCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();
    final categories = ref.read(categoriesProvider).value ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Template name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: itemsCtrl,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Items (one per line)',
                hintText: 'Milk\nBread\nEggs\nButter',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final lines = itemsCtrl.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              if (name.isEmpty || lines.isEmpty) return;

              final items = lines.map((line) {
                final cat = guessCategory(line, categories);
                return TemplateItem(
                  name: line,
                  categoryId: cat?.id ?? 'uncategorised',
                );
              }).toList();

              await ref.read(templatesServiceProvider).addTemplate(
                householdId: householdId,
                name: name,
                items: items,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      itemsCtrl.dispose();
    });
  }
}
