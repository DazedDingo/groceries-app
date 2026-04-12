import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/category.dart';
import '../../providers/categories_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/auth_provider.dart';

const _presetColors = [
  Color(0xFF4CAF50), // Green
  Color(0xFFF44336), // Red
  Color(0xFF2196F3), // Blue
  Color(0xFFFF9800), // Orange
  Color(0xFF9C27B0), // Purple
  Color(0xFF00BCD4), // Cyan
  Color(0xFFFF5722), // Deep Orange
  Color(0xFF607D8B), // Blue Grey
  Color(0xFFE91E63), // Pink
  Color(0xFF795548), // Brown
  Color(0xFF8BC34A), // Light Green
  Color(0xFFFFEB3B), // Yellow
];

class ManageCategoriesScreen extends ConsumerWidget {
  const ManageCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? [];
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final uid = ref.watch(authStateProvider).value?.uid ?? '';
    final service = ref.watch(categoriesServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Categories')),
      body: ReorderableListView.builder(
        itemCount: categories.length,
        onReorder: (oldIndex, newIndex) {
          // Reorder is visual feedback only — Firestore orders by name
        },
        itemBuilder: (_, i) {
          final cat = categories[i];
          return ListTile(
            key: ValueKey(cat.id),
            leading: CircleAvatar(backgroundColor: cat.color, radius: 12),
            title: Text(cat.name),
            trailing: cat.name == 'Uncategorised'
                ? null
                : IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _confirmDelete(context, service, householdId, cat),
                  ),
            onTap: () => _showEditDialog(context, service, householdId, cat),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, service, householdId, uid),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, dynamic service, String householdId, GroceryCategory cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${cat.name}"?'),
        content: const Text('Items will be moved to Uncategorised.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) await service.deleteCategory(householdId, cat.id);
  }

  Future<void> _showEditDialog(
      BuildContext context, dynamic service, String householdId, GroceryCategory cat) async {
    final ctrl = TextEditingController(text: cat.name);
    Color selectedColor = cat.color;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Edit category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 16),
              Text('Color', style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              _ColorGrid(
                selected: selectedColor,
                onSelected: (c) => setD(() => selectedColor = c),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                service.updateCategory(householdId, cat.id,
                    name: ctrl.text.trim(), color: selectedColor);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(
      BuildContext context, dynamic service, String householdId, String uid) async {
    final ctrl = TextEditingController();
    Color selectedColor = _presetColors[0];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 16),
              Text('Color', style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              _ColorGrid(
                selected: selectedColor,
                onSelected: (c) => setD(() => selectedColor = c),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isNotEmpty) {
                  service.addCategory(householdId, name, selectedColor, uid);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorGrid extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onSelected;

  const _ColorGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presetColors.map((color) {
        final isSelected = color.toARGB32() == selected.toARGB32();
        return GestureDetector(
          onTap: () => onSelected(color),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }
}
