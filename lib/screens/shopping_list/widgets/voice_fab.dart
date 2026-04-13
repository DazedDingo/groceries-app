import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/items_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../models/item.dart';
import '../../../services/category_guesser.dart';
import 'add_item_dialog.dart';

class VoiceFab extends ConsumerStatefulWidget {
  final String householdId;
  const VoiceFab({super.key, required this.householdId});
  @override
  ConsumerState<VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends ConsumerState<VoiceFab> {
  final _speech = SpeechToText();
  bool _listening = false;

  Future<void> _listen() async {
    final available = await _speech.initialize();
    if (!available) return;
    setState(() => _listening = true);
    _speech.listen(onResult: (result) {
      if (result.finalResult) {
        _speech.stop();
        if (mounted) {
          setState(() => _listening = false);
          _showDialog(result.recognizedWords);
        }
      }
    });
  }

  Future<void> _showDialog(String initialName) async {
    if (!mounted) return;
    final categories = ref.read(categoriesProvider).value ?? [];
    final guessed = initialName.isNotEmpty ? guessCategory(initialName, categories) : null;

    final result = await showDialog<AddItemResult>(
      context: context,
      builder: (ctx) => AddItemDialog(
        initialName: initialName,
        categories: categories,
        initialCategory: guessed,
      ),
    );

    if (result == null || !mounted) return;
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      await ref.read(itemsServiceProvider).addItem(
        householdId: widget.householdId,
        name: result.name,
        categoryId: result.category?.id ?? 'uncategorised',
        preferredStores: [],
        pantryItemId: null,
        quantity: result.quantity,
        addedBy: AddedBy(
          uid: user?.uid,
          displayName: user?.displayName ?? 'Unknown',
          source: initialName.isNotEmpty ? ItemSource.voiceInApp : ItemSource.app,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add item: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: _listening ? null : _listen,
      child: Icon(_listening ? Icons.mic_off : Icons.mic),
    );
  }
}
