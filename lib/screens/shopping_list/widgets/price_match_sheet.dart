import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/price_link.dart';
import '../../../models/price_product.dart';
import '../../../providers/price_provider.dart';
import '../../../services/price/price_fetch_exception.dart';
import '../../../services/price/price_format.dart';

/// Opens the match sheet for one list item. [link] is the link currently being
/// compared (the user's pick or the auto-match), if any.
Future<void> showPriceMatchSheet(
  BuildContext context, {
  required String itemName,
  required PriceLink? link,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PriceMatchSheet(itemName: itemName, link: link),
  );
}

class _StoreState {
  /// Products from the latest search (null until loaded).
  List<PriceProduct>? results;
  bool loading = false;
  String? error;
  String term;
  bool unavailable;
  final Set<String> checked;

  /// The link's own products for this store (so a pre-checked product still
  /// shows even if the search no longer returns it).
  final List<PriceProduct> fromLink;

  _StoreState({
    required this.term,
    required this.unavailable,
    required this.checked,
    required this.fromLink,
  });

  List<PriceProduct> get candidates {
    final fresh = results ?? const <PriceProduct>[];
    final ids = fresh.map((p) => p.id).toSet();
    return [...fromLink.where((p) => !ids.contains(p.id)), ...fresh];
  }
}

class PriceMatchSheet extends ConsumerStatefulWidget {
  final String itemName;
  final PriceLink? link;
  const PriceMatchSheet({super.key, required this.itemName, this.link});

  @override
  ConsumerState<PriceMatchSheet> createState() => _PriceMatchSheetState();
}

class _PriceMatchSheetState extends ConsumerState<PriceMatchSheet> {
  late final Map<PriceStore, _StoreState> _stores;
  final _searchControllers = {
    PriceStore.asda: TextEditingController(),
    PriceStore.costco: TextEditingController(),
  };
  PriceStore _current = PriceStore.asda;

  @override
  void initState() {
    super.initState();
    final link = widget.link;
    _StoreState make(PriceStore s) {
      final products = s == PriceStore.asda
          ? (link?.asda ?? const <PriceProduct>[])
          : (link?.costco ?? const <PriceProduct>[]);
      return _StoreState(
        term: widget.itemName,
        unavailable: s == PriceStore.asda
            ? (link?.asdaUnavailable ?? false)
            : (link?.costcoUnavailable ?? false),
        checked: products.map((p) => p.id).toSet(),
        fromLink: products,
      );
    }

    _stores = {
      PriceStore.asda: make(PriceStore.asda),
      PriceStore.costco: make(PriceStore.costco),
    };
    for (final s in PriceStore.values) {
      _searchControllers[s]!.text = widget.itemName;
      unawaited(_load(s));
    }
  }

  @override
  void dispose() {
    for (final c in _searchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load(PriceStore store) async {
    final st = _stores[store]!;
    setState(() {
      st.loading = true;
      st.error = null;
    });
    try {
      final r = await ref
          .read(priceSearchServiceProvider)
          .searchStore(store, st.term);
      if (!mounted) return;
      setState(() {
        st.results = r;
        st.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        st.error = e is PriceFetchException ? e.message : e.toString();
        st.loading = false;
      });
    }
  }

  void _save() {
    final notifier = ref.read(priceCompareControllerProvider.notifier);
    final asda = _stores[PriceStore.asda]!;
    final costco = _stores[PriceStore.costco]!;
    List<PriceProduct> picked(_StoreState s) => s.unavailable
        ? const []
        : s.candidates.where((p) => s.checked.contains(p.id)).toList();
    final a = picked(asda);
    final c = picked(costco);
    final mode = (a.length > 1 || c.length > 1)
        ? LinkMode.anyOf
        : LinkMode.exact;
    final key = PriceLink.keyFor(widget.itemName);
    // Close first: the write only completes once the server acknowledges it,
    // which can take a while offline.
    Navigator.of(context).pop();
    unawaited(
      notifier.confirmMatch(
        key,
        asda: a,
        costco: c,
        mode: mode,
        asdaUnavailable: asda.unavailable,
        costcoUnavailable: costco.unavailable,
      ),
    );
  }

  void _reset() {
    final notifier = ref.read(priceCompareControllerProvider.notifier);
    final key = PriceLink.keyFor(widget.itemName);
    Navigator.of(context).pop();
    unawaited(notifier.resetMatch(key));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final confirmed = widget.link?.userConfirmed ?? false;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.itemName, style: text.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<PriceStore>(
                key: const ValueKey('match-store-segments'),
                segments: const [
                  ButtonSegment(value: PriceStore.asda, label: Text('Asda')),
                  ButtonSegment(
                    value: PriceStore.costco,
                    label: Text('Costco'),
                  ),
                ],
                selected: {_current},
                onSelectionChanged: (s) => setState(() => _current = s.first),
              ),
            ),
          ),
          Expanded(child: _storeList(_current, scroll)),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (confirmed)
                    TextButton(
                      key: const ValueKey('match-reset'),
                      onPressed: _reset,
                      child: const Text('Reset to automatic'),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('match-save'),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storeList(PriceStore store, ScrollController scroll) {
    final scheme = Theme.of(context).colorScheme;
    final st = _stores[store]!;
    final name = store == PriceStore.asda ? 'Asda' : 'Costco';
    final candidates = st.candidates;
    return ListView(
      key: ValueKey('match-list-${store.value}'),
      controller: scroll,
      children: [
        SwitchListTile(
          key: ValueKey('match-unavailable-${store.value}'),
          title: const Text('Not sold here'),
          subtitle: Text('Ignore $name for this item'),
          value: st.unavailable,
          onChanged: (v) => setState(() => st.unavailable = v),
        ),
        ExpansionTile(
          key: ValueKey('match-search-${store.value}'),
          title: const Text('Search for something else'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchControllers[store],
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Search $name',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                    onPressed: () => _research(store),
                  ),
                ),
                onSubmitted: (_) => _research(store),
              ),
            ),
          ],
        ),
        if (st.loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (st.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(st.error!)),
                TextButton(
                  onPressed: () => _load(store),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        if (!st.loading && st.error == null && candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('No results at $name')),
          ),
        for (final p in candidates)
          Opacity(
            opacity: st.unavailable ? 0.5 : 1,
            child: _ProductTile(
              product: p,
              checked: st.checked.contains(p.id),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  st.checked.add(p.id);
                } else {
                  st.checked.remove(p.id);
                }
              }),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _research(PriceStore store) {
    final term = _searchControllers[store]!.text.trim();
    if (term.isEmpty) return;
    _stores[store]!.term = term;
    unawaited(_load(store));
  }
}

class _ProductTile extends StatelessWidget {
  final PriceProduct product;
  final bool checked;
  final ValueChanged<bool?> onChanged;
  const _ProductTile({
    required this.product,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final basis = displayBasis(product);
    final unit = basis == null ? null : formatUnitCost(product, basis);
    final price = [
      formatPounds(product.price),
      ?unit,
      if (!product.inStock) 'out of stock',
    ].join(' · ');
    return CheckboxListTile(
      value: checked,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(product.name),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(price),
          if (product.offer != null)
            PriceTag(
              label: product.offer!,
              background: scheme.tertiaryContainer,
              foreground: scheme.onTertiaryContainer,
            ),
        ],
      ),
    );
  }
}

/// Small rounded label used for offers and match flags.
class PriceTag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const PriceTag({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: foreground),
    ),
  );
}
