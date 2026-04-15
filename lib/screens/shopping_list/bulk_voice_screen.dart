import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../models/item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/gemini_key_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/items_provider.dart';
import '../../services/bulk_voice_parser.dart';
import '../../services/category_guesser.dart';

/// Hands-free pantry catalogue screen. Continuously listens, periodically
/// sends the running transcript to Gemini Flash to extract a structured list
/// (handling corrections, dedupes, filler words), and lets the user review
/// before bulk-adding to the shopping list.
class BulkVoiceScreen extends ConsumerStatefulWidget {
  const BulkVoiceScreen({super.key});
  @override
  ConsumerState<BulkVoiceScreen> createState() => _BulkVoiceScreenState();
}

class _BulkVoiceScreenState extends ConsumerState<BulkVoiceScreen> {
  final _speech = SpeechToText();
  bool _available = false;
  bool _listening = false;
  bool _parsing = false;
  bool _initError = false;
  String _liveTranscript = '';
  String _committedTranscript = '';
  Timer? _debounce;
  List<ParsedVoiceItem> _items = [];
  String? _errorMessage;

  String get _fullTranscript {
    if (_liveTranscript.isEmpty) return _committedTranscript;
    if (_committedTranscript.isEmpty) return _liveTranscript;
    return '$_committedTranscript $_liveTranscript';
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (e) {
          if (mounted) setState(() => _errorMessage = e.errorMsg);
        },
      );
    } catch (_) {
      _available = false;
    }
    if (!mounted) return;
    setState(() => _initError = !_available);
    if (_available) _startListening();
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'done' || status == 'notListening') {
      // STT auto-stops after a window — restart if user still wants to listen.
      if (_listening) _restartListening();
    }
  }

  void _startListening() {
    if (!_available) return;
    setState(() {
      _listening = true;
      _errorMessage = null;
    });
    _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _liveTranscript = result.recognizedWords;
        });
        if (result.finalResult) {
          _committedTranscript = _committedTranscript.isEmpty
              ? _liveTranscript
              : '$_committedTranscript $_liveTranscript';
          _liveTranscript = '';
          _scheduleParse();
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  void _restartListening() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_listening) return;
      _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() => _liveTranscript = result.recognizedWords);
          if (result.finalResult) {
            _committedTranscript = _committedTranscript.isEmpty
                ? _liveTranscript
                : '$_committedTranscript $_liveTranscript';
            _liveTranscript = '';
            _scheduleParse();
          }
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
    });
  }

  void _stopListening() {
    setState(() => _listening = false);
    _speech.stop();
    _scheduleParse(immediate: true);
  }

  void _scheduleParse({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      Duration(milliseconds: immediate ? 0 : 1500),
      _runParse,
    );
  }

  Future<void> _runParse() async {
    final transcript = _fullTranscript.trim();
    if (transcript.isEmpty) return;
    final key = ref.read(geminiKeyProvider);
    if (key.isEmpty) {
      setState(() => _errorMessage =
          'No Gemini API key set. Add one in Settings → Bulk voice add.');
      return;
    }
    setState(() => _parsing = true);
    try {
      final parser = BulkVoiceParser(apiKey: key);
      final parsed = await parser.parse(transcript);
      parser.dispose();
      if (!mounted) return;
      setState(() {
        _items = parsed;
        _parsing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _errorMessage = 'Parse failed: $e';
      });
    }
  }

  Future<void> _addAllToList() async {
    if (_items.isEmpty) return;
    final householdId = ref.read(householdIdProvider).value ?? '';
    if (householdId.isEmpty) return;
    final categories = ref.read(categoriesProvider).value ?? [];
    final overrides = ref.read(categoryOverridesProvider).value ?? {};
    final user = ref.read(authStateProvider).valueOrNull;
    final addedBy = AddedBy(
      uid: user?.uid,
      displayName: user?.displayName ?? 'Unknown',
      source: ItemSource.voiceInApp,
    );
    final service = ref.read(itemsServiceProvider);

    int success = 0;
    final failures = <String>[];
    for (final item in _items) {
      try {
        final cat = guessCategory(item.name, categories, overrides);
        await service.addItem(
          householdId: householdId,
          name: item.name,
          categoryId: cat?.id ?? 'uncategorised',
          preferredStores: [],
          pantryItemId: null,
          quantity: item.quantity,
          unit: item.unit,
          addedBy: addedBy,
        );
        success++;
      } catch (e) {
        failures.add('${item.name}: $e');
      }
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(failures.isEmpty
          ? 'Added $success items to your list'
          : 'Added $success, failed ${failures.length}'),
    ));
    navigator.pop();
  }

  void _editItem(int index) async {
    final current = _items[index];
    final qtyCtrl = TextEditingController(text: '${current.quantity}');
    final nameCtrl = TextEditingController(text: current.name);
    final unitCtrl = TextEditingController(text: current.unit ?? '');
    final result = await showDialog<ParsedVoiceItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final qty = int.tryParse(qtyCtrl.text) ?? current.quantity;
              final unit = unitCtrl.text.trim();
              Navigator.pop(
                ctx,
                ParsedVoiceItem(
                  name: nameCtrl.text.trim(),
                  quantity: qty,
                  unit: unit.isEmpty ? null : unit,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() => _items[index] = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasKey = ref.watch(geminiKeyProvider).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk voice add'),
        actions: [
          if (_parsing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-parse transcript',
            onPressed: _fullTranscript.isEmpty || _parsing ? null : _runParse,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasKey)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.errorContainer,
              child: Text(
                'Set a Gemini API key in Settings → Bulk voice add to enable parsing.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          if (_initError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.errorContainer,
              child: Text(
                'Microphone unavailable. Grant mic permission in your device settings.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.errorContainer,
              child: Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          // Live transcript card
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _listening ? Icons.mic : Icons.mic_off,
                          color: _listening ? Colors.red : theme.disabledColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _listening ? 'Listening…' : 'Stopped',
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: Icon(_listening ? Icons.stop : Icons.play_arrow),
                          label: Text(_listening ? 'Stop' : 'Resume'),
                          onPressed: !_available
                              ? null
                              : (_listening ? _stopListening : _startListening),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fullTranscript.isEmpty
                          ? 'Say things like: "1 coriander, next, 2 cinnamon sticks". You can correct yourself ("oh wait, actually 3").'
                          : _fullTranscript,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _fullTranscript.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Items (${_items.length})',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_items.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                    onPressed: () => setState(() {
                      _items = [];
                      _committedTranscript = '';
                      _liveTranscript = '';
                    }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _parsing
                            ? 'Parsing…'
                            : 'Items will appear here as you speak.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final item = _items[i];
                      final qtyLabel = item.unit != null
                          ? '${item.quantity} ${item.unit}'
                          : '${item.quantity}';
                      return Dismissible(
                        key: ValueKey('${item.name}_$i'),
                        background: Container(
                          color: theme.colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: Icon(Icons.delete,
                              color: theme.colorScheme.onErrorContainer),
                        ),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) =>
                            setState(() => _items.removeAt(i)),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(qtyLabel)),
                          title: Text(item.name),
                          trailing: const Icon(Icons.edit, size: 18),
                          onTap: () => _editItem(i),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _items.isEmpty ? null : _addAllToList,
                icon: const Icon(Icons.playlist_add),
                label: Text('Add ${_items.length} to list'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
