import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/household_provider.dart';

class PantryItemDetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  const PantryItemDetailScreen({super.key, required this.itemId});
  @override
  ConsumerState<PantryItemDetailScreen> createState() => _PantryItemDetailScreenState();
}

class _PantryItemDetailScreenState extends ConsumerState<PantryItemDetailScreen> {
  int? _selectedDays;

  @override
  Widget build(BuildContext context) {
    final pantry = ref.watch(pantryProvider).value ?? [];
    final item = pantry.where((p) => p.id == widget.itemId).firstOrNull;
    if (item == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    _selectedDays ??= item.restockAfterDays;
    final householdId = ref.watch(householdIdProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Optimal quantity: ${item.optimalQuantity}'),
          Text('Current quantity: ${item.currentQuantity}'),
          const SizedBox(height: 24),
          const Text('Restock nudge interval'),
          const SizedBox(height: 8),
          DropdownButton<int?>(
            value: _selectedDays,
            items: const [
              DropdownMenuItem(value: null, child: Text('Off')),
              DropdownMenuItem(value: 3, child: Text('Every 3 days')),
              DropdownMenuItem(value: 7, child: Text('Every 7 days')),
              DropdownMenuItem(value: 14, child: Text('Every 14 days')),
              DropdownMenuItem(value: 30, child: Text('Every 30 days')),
            ],
            onChanged: (val) {
              setState(() => _selectedDays = val);
              ref.read(pantryServiceProvider).updateItem(
                  householdId, widget.itemId, {'restockAfterDays': val});
            },
          ),
        ]),
      ),
    );
  }
}
