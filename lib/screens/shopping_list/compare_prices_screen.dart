import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/price_link.dart';
import '../../models/price_product.dart';
import '../../providers/household_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/price_provider.dart';
import '../../services/price/auto_match.dart';
import '../../services/price/price_compare.dart';
import '../../services/price/price_format.dart';
import '../../services/price/price_search_service.dart';
import '../shared/empty_state.dart';
import 'widgets/price_match_sheet.dart';

/// How old a result may be before opening the screen re-runs the comparison.
const priceResultMaxAge = Duration(hours: 6);

class ComparePricesScreen extends ConsumerStatefulWidget {
  /// Injectable for tests.
  final DateTime Function()? clock;
  const ComparePricesScreen({super.key, this.clock});

  @override
  ConsumerState<ComparePricesScreen> createState() =>
      _ComparePricesScreenState();
}

class _ComparePricesScreenState extends ConsumerState<ComparePricesScreen> {
  bool _autoRunChecked = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _maybeAutoRun() {
    final s = ref.read(priceCompareControllerProvider);
    if (s.running) return;
    final at = s.lastRunAt;
    final fresh =
        s.last != null &&
        at != null &&
        _now().difference(at) < priceResultMaxAge;
    if (!fresh) {
      unawaited(ref.read(priceCompareControllerProvider.notifier).compare());
    }
  }

  Future<void> _editFees(PriceFees current) async {
    final fees = await showDialog<PriceFees>(
      context: context,
      builder: (_) => _FeesDialog(initial: current),
    );
    if (fees == null || !mounted) return;
    final controller = ref.read(priceCompareControllerProvider.notifier);
    // Show the new totals straight away; persisting can lag offline.
    controller.updateFees(fees);
    try {
      final hid = await ref.read(householdIdProvider.future);
      if (hid == null) throw StateError('No household');
      await ref.read(priceLinksServiceProvider).saveSettings(hid, fees);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save delivery fees: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider);
    final state = ref.watch(priceCompareControllerProvider);
    final fees =
        state.last?.fees ??
        ref.watch(priceFeesProvider).valueOrNull ??
        const PriceFees();

    final loaded = items.valueOrNull;
    if (loaded != null && loaded.isNotEmpty && !_autoRunChecked) {
      _autoRunChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAutoRun();
      });
    }
    final empty = loaded != null && loaded.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare prices'),
        actions: [
          IconButton(
            key: const ValueKey('compare-fees'),
            icon: const Icon(Icons.local_shipping_outlined),
            tooltip: 'Delivery fees',
            onPressed: () => _editFees(fees),
          ),
          IconButton(
            key: const ValueKey('compare-refresh'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh prices',
            onPressed: state.running || empty
                ? null
                : () => unawaited(
                    ref.read(priceCompareControllerProvider.notifier).compare(),
                  ),
          ),
        ],
      ),
      body: empty
          ? const EmptyState(
              icon: Icons.price_change_outlined,
              title: 'Add items to your list to compare prices',
            )
          : _Body(state: state, now: _now()),
    );
  }
}

class _Body extends StatelessWidget {
  final PriceCompareState state;
  final DateTime now;
  const _Body({required this.state, required this.now});

  @override
  Widget build(BuildContext context) {
    final last = state.last;
    final progress = state.progress;
    final errors = state.running
        ? (progress?.storeErrors ?? const <PriceStore, String>{})
        : (last?.storeErrors ?? const <PriceStore, String>{});

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (state.running) _ProgressBar(progress: progress),
        if (!state.running && last != null && state.lastRunAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              formatUpdatedAgo(state.lastRunAt!, now),
              key: const ValueKey('compare-updated'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (state.error != null)
          _ErrorCard(
            key: const ValueKey('compare-error'),
            message: 'Something went wrong: ${state.error}',
          ),
        for (final e in errors.entries)
          _StoreErrorCard(store: e.key, message: e.value),
        if (last == null && !state.running && state.error == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nothing to show yet.')),
          ),
        if (last != null) ..._result(context, last),
      ],
    );
  }

  List<Widget> _result(BuildContext context, PriceRunResult run) {
    final r = run.result;
    final plan = r.splitPlan;
    final unpriced = [
      for (final l in r.lines)
        if (l.status == LineStatus.unlinked ||
            l.status == LineStatus.unavailable)
          l,
    ];
    return [
      _SummaryCard(run: run),
      if (plan.costcoLines.isNotEmpty) ...[
        _SectionHeader('From Costco', plan.costcoLines.length),
        for (final l in plan.costcoLines)
          _LineTile(line: l, run: run, store: PriceStore.costco),
      ],
      if (plan.asdaLines.isNotEmpty) ...[
        _SectionHeader('From Asda', plan.asdaLines.length),
        for (final l in plan.asdaLines)
          _LineTile(line: l, run: run, store: PriceStore.asda),
      ],
      if (unpriced.isNotEmpty) ...[
        _SectionHeader("Couldn't price", unpriced.length),
        for (final l in unpriced) _LineTile(line: l, run: run, store: null),
      ],
    ];
  }
}

class _ProgressBar extends StatelessWidget {
  final PriceRunProgress? progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final value = (p == null || p.total == 0) ? null : p.done / p.total;
    final label = p == null
        ? 'Checking prices…'
        : 'Checking prices… ${p.done}/${p.total}'
              '${p.currentItem == null ? '' : ' · ${p.currentItem}'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            key: const ValueKey('compare-progress'),
            value: value,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            key: const ValueKey('compare-progress-label'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Widget? action;
  const _ErrorCard({super.key, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            if (action != null)
              Align(alignment: Alignment.centerRight, child: action),
          ],
        ),
      ),
    );
  }
}

class _StoreErrorCard extends StatelessWidget {
  final PriceStore store;
  final String message;
  const _StoreErrorCard({required this.store, required this.message});

  @override
  Widget build(BuildContext context) {
    final asda = store == PriceStore.asda;
    return _ErrorCard(
      key: ValueKey('store-error-${store.value}'),
      message: asda
          ? "Asda didn't respond. Open the Price lab once (it passes Asda's "
                'security check), then tap refresh.'
          : "Costco didn't respond ($message). Tap refresh to try again.",
      action: asda
          ? TextButton(
              key: const ValueKey('open-price-lab'),
              onPressed: () => context.push('/settings/price-lab'),
              child: Text(
                'Open Price lab',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            )
          : null,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final PriceRunResult run;
  const _SummaryCard({required this.run});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = run.result;
    final plan = r.splitPlan;
    final text = describeRecommendation(r, run.fees);
    final split = r.recommendation == Recommendation.split;
    final unpriced = r.unlinkedCount + r.unavailableCount;

    String order(String store, int n, double spend, double fee) =>
        '$store · ${itemsLabel(n)} · ${formatPounds(spend)} + '
        '${formatPounds(fee)} delivery';

    return Card(
      key: const ValueKey('compare-summary'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.headline,
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DefaultTextStyle.merge(
              style: TextStyle(color: scheme.onSecondaryContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (plan.costcoLines.isNotEmpty)
                    Text(
                      order(
                        'Costco',
                        plan.costcoLines.length,
                        plan.costcoSpend,
                        plan.costcoFee,
                      ),
                    ),
                  if (plan.asdaLines.isNotEmpty)
                    Text(
                      order(
                        'Asda',
                        plan.asdaLines.length,
                        plan.asdaSpend,
                        plan.asdaFee,
                      ),
                    ),
                  if (text.why != null) ...[
                    const SizedBox(height: 8),
                    Text(text.why!),
                  ],
                  if (split) ...[
                    const SizedBox(height: 8),
                    Text(r.summary),
                    const SizedBox(height: 8),
                    Text(
                      r.splitNetSaving > 0
                          ? 'Net saving ${formatPounds(r.splitNetSaving)}'
                          : 'Net ${formatPounds(r.splitNetSaving)} '
                                'vs all Asda (Costco is needed anyway)',
                      key: const ValueKey('compare-net-saving'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (unpriced > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      unpriced == 1
                          ? "1 item couldn't be priced"
                          : "$unpriced items couldn't be priced",
                      key: const ValueKey('compare-unpriced'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader(this.title, this.count);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      '$title ($count)',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _LineTile extends ConsumerWidget {
  final LineComparison line;
  final PriceRunResult run;

  /// Which store this row buys from; null for unpriced rows.
  final PriceStore? store;
  const _LineTile({required this.line, required this.run, required this.store});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = line.line.itemName;
    final qty = line.line.qty;
    final key = PriceLink.keyFor(name);
    final link = run.effectiveLinks[key];
    final auto = run.auto[key];
    final product = switch (store) {
      PriceStore.costco => line.bestCostco,
      PriceStore.asda => line.bestAsda,
      null => null,
    };

    final lines = <String>[];
    if (product != null) {
      lines.add(product.name);
      final basis = line.basis ?? displayBasis(product);
      final unit = basis == null ? null : formatUnitCost(product, basis);
      lines.add([formatPackPrice(product, qty), ?unit].join(' · '));
      if (store == PriceStore.costco) {
        final saving = formatCostcoSaving(line);
        if (saving != null) {
          lines.add(saving);
        } else if (line.status == LineStatus.costcoOnly) {
          lines.add('Not available at Asda');
        }
      }
    } else {
      lines.add(unpricedReason(line, auto));
    }

    final tags = <Widget>[];
    void tag(String label, Color bg, Color fg) =>
        tags.add(PriceTag(label: label, background: bg, foreground: fg));
    if (product != null) {
      if (product.offer != null) {
        tag(
          product.offer!,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        );
      }
      final mb = product.promos.where((p) => p.multiBuy != null);
      if (mb.isNotEmpty) {
        tag(
          mb.first.name,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        );
      }
      if (product.stale) {
        tag(
          'may be out of date',
          scheme.errorContainer,
          scheme.onErrorContainer,
        );
      }
    }
    final confirmed = link?.userConfirmed ?? false;
    if (confirmed) {
      tag('your pick', scheme.primaryContainer, scheme.onPrimaryContainer);
    } else if (auto?.asdaConfidence == MatchConfidence.low &&
        store != PriceStore.costco) {
      tag('check match', scheme.errorContainer, scheme.onErrorContainer);
    }

    return ListTile(
      key: ValueKey('compare-row-$key'),
      title: Text(qty > 1 ? '$name × $qty' : name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Text(
              l,
              style: l == lines.first && product != null
                  ? null
                  : theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, runSpacing: 4, children: tags),
            ),
        ],
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: () => showPriceMatchSheet(context, itemName: name, link: link),
    );
  }
}

class _FeesDialog extends StatefulWidget {
  final PriceFees initial;
  const _FeesDialog({required this.initial});

  @override
  State<_FeesDialog> createState() => _FeesDialogState();
}

class _FeesDialogState extends State<_FeesDialog> {
  final _form = GlobalKey<FormState>();
  late final _asda = TextEditingController(
    text: widget.initial.asdaDelivery.toStringAsFixed(2),
  );
  late final _costco = TextEditingController(
    text: widget.initial.costcoDelivery.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _asda.dispose();
    _costco.dispose();
    super.dispose();
  }

  static double? _parse(String? s) =>
      double.tryParse((s ?? '').trim().replaceAll(',', '.'));

  static String? _validate(String? s) {
    final v = _parse(s);
    if (v == null) return 'Enter an amount';
    if (v < 0 || v > 50) return 'Between £0 and £50';
    return null;
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      PriceFees(
        asdaDelivery: _parse(_asda.text)!,
        costcoDelivery: _parse(_costco.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delivery fees'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('fee-asda'),
              controller: _asda,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Asda delivery',
                prefixText: '£',
              ),
              validator: _validate,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('fee-costco'),
              controller: _costco,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Costco delivery',
                prefixText: '£',
              ),
              validator: _validate,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('fee-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
