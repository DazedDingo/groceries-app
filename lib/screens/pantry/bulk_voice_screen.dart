import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../providers/categories_provider.dart';
import '../../providers/gemini_key_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../services/bulk_voice_parser.dart';
import '../../services/category_guesser.dart';

/// One row in the pantry voice review list. The Gemini parser hands us a
/// single "quantity" per utterance; we seed both `current` and `optimal`
/// from it so users get a sensible starting point, then let them split the
/// two via the edit dialog before bulk-committing. Keeping this local to the
/// screen (instead of extending ParsedVoiceItem) avoids polluting the
/// shopping-list surface area, which only needs a single quantity.
class PantryReviewItem {
  final String name;
  final int currentQuantity;
  final int optimalQuantity;
  final String? unit;
  const PantryReviewItem({
    required this.name,
    required this.currentQuantity,
    required this.optimalQuantity,
    this.unit,
  });

  PantryReviewItem copyWith({
    String? name,
    int? currentQuantity,
    int? optimalQuantity,
    String? unit,
  }) => PantryReviewItem(
        name: name ?? this.name,
        currentQuantity: currentQuantity ?? this.currentQuantity,
        optimalQuantity: optimalQuantity ?? this.optimalQuantity,
        unit: unit ?? this.unit,
      );

  factory PantryReviewItem.fromVoice(ParsedVoiceItem v) => PantryReviewItem(
        name: v.name,
        currentQuantity: v.quantity,
        optimalQuantity: v.quantity,
        unit: v.unit,
      );
}

/// Hands-free pantry cataloguing by voice. Mirrors the shopping-list bulk
/// voice screen: continuous dictation, silence-auto-advance, Gemini Flash
/// parsing. Each dictated item becomes a [PantryReviewItem] with `current`
/// and `optimal` both seeded from the spoken quantity — the review list
/// exposes both numbers so the user can split them before committing.
class PantryBulkVoiceScreen extends ConsumerStatefulWidget {
  final bool autoStartListening;

  /// How long of a gap in incoming speech results before the app auto-advances
  /// to the next item (plays a ding + commits the live transcript).
  final Duration silenceAutoAdvance;

  const PantryBulkVoiceScreen({
    super.key,
    this.autoStartListening = true,
    this.silenceAutoAdvance = const Duration(milliseconds: 2500),
  });

  @override
  ConsumerState<PantryBulkVoiceScreen> createState() =>
      PantryBulkVoiceScreenState();
}

@visibleForTesting
class PantryBulkVoiceScreenState
    extends ConsumerState<PantryBulkVoiceScreen> {
  final _speech = SpeechToText();
  bool _available = false;
  bool _listening = false;
  bool _parsing = false;
  bool _initError = false;
  String _liveTranscript = '';
  String _committedTranscript = '';
  Timer? _debounce;
  Timer? _silenceTimer;
  List<PantryReviewItem> _items = [];
  String? _errorMessage;
  int _parseSeq = 0;

  @visibleForTesting
  void seedForTest(
      {String transcript = '', List<PantryReviewItem> items = const []}) {
    setState(() {
      _committedTranscript = transcript;
      _liveTranscript = '';
      _items = List.of(items);
    });
  }

  @visibleForTesting
  Future<void> triggerParseForTest() => _runParse();

  @visibleForTesting
  void setListeningForTest(bool v) {
    _listening = v;
  }

  @visibleForTesting
  void triggerSilenceTimeoutForTest() => _onSilenceTimeout();

  @visibleForTesting
  Future<void> triggerAddAllForTest() => _addAllToPantry();

  String get _fullTranscript {
    if (_liveTranscript.isEmpty) return _committedTranscript;
    if (_committedTranscript.isEmpty) return _liveTranscript;
    return '$_committedTranscript $_liveTranscript';
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoStartListening) _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _silenceTimer?.cancel();
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
      onResult: _onSpeechResult,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
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
    _armSilenceTimer();
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(widget.silenceAutoAdvance, _onSilenceTimeout);
  }

  void _onSilenceTimeout() {
    if (!mounted || !_listening) return;
    final hasSomething = _liveTranscript.trim().isNotEmpty ||
        _committedTranscript.trim().isNotEmpty;
    if (!hasSomething) return;
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
    setState(() {
      if (_liveTranscript.trim().isNotEmpty) {
        _committedTranscript = _committedTranscript.isEmpty
            ? _liveTranscript
            : '$_committedTranscript $_liveTranscript';
        _liveTranscript = '';
      }
      if (!_committedTranscript.trimRight().toLowerCase().endsWith('next')) {
        _committedTranscript = '${_committedTranscript.trimRight()} next ';
      }
    });
    _scheduleParse(immediate: true);
  }

  void _restartListening() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_listening) return;
      _speech.listen(
        onResult: _onSpeechResult,
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
    _silenceTimer?.cancel();
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
    final mySeq = ++_parseSeq;
    setState(() => _parsing = true);
    try {
      final parseFn = ref.read(bulkVoiceParseFnProvider);
      final parsed = await parseFn(transcript);
      if (!mounted || mySeq != _parseSeq) return;
      // Preserve any per-item current/optimal tweaks the user made before a
      // re-parse triggered by continued dictation. We match on (name, unit);
      // reparses add NEW items to the end, they don't overwrite existing
      // ones, so the user's edits survive.
      setState(() {
        final existing = {
          for (final item in _items) _matchKey(item.name, item.unit): item,
        };
        _items = parsed.map((p) {
          final prev = existing[_matchKey(p.name, p.unit)];
          return prev ?? PantryReviewItem.fromVoice(p);
        }).toList();
        _parsing = false;
      });
    } catch (e) {
      if (!mounted || mySeq != _parseSeq) return;
      setState(() {
        _parsing = false;
        _errorMessage = 'Parse failed: $e';
      });
    }
  }

  String _matchKey(String name, String? unit) =>
      '${name.trim().toLowerCase()}|${unit?.trim().toLowerCase() ?? ''}';

  Future<void> _addAllToPantry() async {
    if (_items.isEmpty) return;
    final householdId = await ref.read(householdIdProvider.future) ?? '';
    if (householdId.isEmpty) return;
    final categories = ref.read(categoriesProvider).value ?? [];
    final overrides = ref.read(categoryOverridesProvider).value ?? {};
    final service = ref.read(pantryServiceProvider);

    final payload = _items.map((item) {
      final cat = guessCategory(item.name, categories, overrides);
      return (
        name: item.name,
        categoryId: cat?.id ?? 'uncategorised',
        currentQuantity: item.currentQuantity,
        optimalQuantity: item.optimalQuantity,
        unit: item.unit,
      );
    }).toList();

    int added = 0;
    String? error;
    try {
      await service.addItems(householdId: householdId, items: payload);
      added = payload.length;
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(error == null
          ? 'Added $added items to your pantry'
          : 'Bulk add failed: $error'),
    ));
    if (error == null) navigator.pop();
  }

  void _editItem(int index) async {
    final current = _items[index];
    final nameCtrl = TextEditingController(text: current.name);
    final currentCtrl =
        TextEditingController(text: '${current.currentQuantity}');
    final optimalCtrl =
        TextEditingController(text: '${current.optimalQuantity}');
    final unitCtrl = TextEditingController(text: current.unit ?? '');
    final result = await showDialog<PantryReviewItem>(
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
                    controller: currentCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Current',
                      helperText: 'On hand now',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: optimalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Optimal',
                      helperText: 'Target stock',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(labelText: 'Unit (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final cur =
                  int.tryParse(currentCtrl.text) ?? current.currentQuantity;
              final opt =
                  int.tryParse(optimalCtrl.text) ?? current.optimalQuantity;
              final unit = unitCtrl.text.trim();
              Navigator.pop(
                ctx,
                PantryReviewItem(
                  name: nameCtrl.text.trim(),
                  currentQuantity: cur,
                  optimalQuantity: opt,
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
        title: const Text('Bulk voice add to pantry'),
        actions: [
          if (_parsing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-parse transcript',
            onPressed:
                _fullTranscript.isEmpty || _parsing ? null : _runParse,
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
                          color: _listening
                              ? Colors.red
                              : theme.disabledColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _listening ? 'Listening…' : 'Stopped',
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: Icon(
                              _listening ? Icons.stop : Icons.play_arrow),
                          label: Text(_listening ? 'Stop' : 'Resume'),
                          onPressed: !_available
                              ? null
                              : (_listening
                                  ? _stopListening
                                  : _startListening),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fullTranscript.isEmpty
                          ? 'Dictate your staples. E.g. "3 pasta, next, 2 tins of tomatoes, 6 eggs". Each number seeds both current and optimal — tap a row to split them.'
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
                      final unitSuffix =
                          item.unit != null ? ' ${item.unit}' : '';
                      final subtitle =
                          'Current ${item.currentQuantity}$unitSuffix  ·  '
                          'Optimal ${item.optimalQuantity}$unitSuffix';
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
                          leading: CircleAvatar(
                            child: Text(
                              '${item.currentQuantity}/${item.optimalQuantity}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          title: Text(item.name),
                          subtitle: Text(subtitle),
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
                onPressed: _items.isEmpty ? null : _addAllToPantry,
                icon: const Icon(Icons.kitchen),
                label: Text('Add ${_items.length} to pantry'),
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
