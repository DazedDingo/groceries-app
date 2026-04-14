import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pantry_item.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/household_provider.dart';

class ManageLocationsScreen extends ConsumerWidget {
  const ManageLocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(householdIdProvider).value ?? '';
    final customAsync = ref.watch(customLocationsProvider);
    final customLocations = customAsync.value ?? [];
    final locationService = ref.watch(locationServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Locations')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Built-in locations',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...PantryLocation.values.map((loc) => ListTile(
                leading: Icon(_icon(loc)),
                title: Text(loc.label),
                dense: true,
              )),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Text('Custom locations',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddDialog(context, householdId, locationService),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          if (customLocations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No custom locations yet.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ...customLocations.map((label) => ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(label),
                  dense: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Remove location?'),
                          content: Text(
                              '"$label" will be removed. Items using it will still show the label until you change them.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        locationService.removeLocation(householdId, label);
                      }
                    },
                  ),
                )),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, householdId, locationService),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, String householdId,
      dynamic locationService) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add location'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Location name',
            hintText: 'e.g. Garage, Spice rack',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      locationService.addLocation(householdId, result);
    }
  }

  IconData _icon(PantryLocation loc) => switch (loc) {
        PantryLocation.fridge => Icons.kitchen,
        PantryLocation.freezer => Icons.ac_unit,
        PantryLocation.pantry => Icons.shelves,
        PantryLocation.counter => Icons.countertops,
        PantryLocation.other => Icons.place_outlined,
      };
}
