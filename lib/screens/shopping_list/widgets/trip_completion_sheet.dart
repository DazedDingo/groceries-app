import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/history_entry.dart';
import '../../../services/wallet_launcher.dart';

class TripStats {
  final int itemCount;
  final Duration duration;
  final Map<String, int> perPerson;
  final bool firstOfDay;

  const TripStats({
    required this.itemCount,
    required this.duration,
    required this.perPerson,
    required this.firstOfDay,
  });
}

/// Compute trip stats from [history]. A "trip" is the set of bought entries
/// within [tripWindow] of the most-recent bought entry. [now] is injected for
/// testability; production callers pass `DateTime.now()`.
///
/// Returns null when no bought entries fall inside the window — caller should
/// skip the sheet (list likely emptied by deletes, not checkouts).
TripStats? computeTripStats({
  required List<HistoryEntry> history,
  required DateTime now,
  required bool firstOfDay,
  Duration tripWindow = const Duration(hours: 4),
}) {
  final bought = history.where((h) => h.action == HistoryAction.bought).toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  if (bought.isEmpty) return null;

  final latestAt = bought.first.at;
  final window = bought
      .where((h) => latestAt.difference(h.at).abs() <= tripWindow)
      .toList();
  if (window.isEmpty) return null;

  final earliestAt = window.last.at;
  final duration = latestAt.difference(earliestAt);

  final perPerson = <String, int>{};
  for (final h in window) {
    perPerson[h.byName] = (perPerson[h.byName] ?? 0) + 1;
  }

  return TripStats(
    itemCount: window.length,
    duration: duration,
    perPerson: perPerson,
    firstOfDay: firstOfDay,
  );
}

String formatTripDuration(Duration d) {
  if (d.inMinutes < 1) return 'moments';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final hours = d.inHours;
  final mins = d.inMinutes - hours * 60;
  if (mins == 0) return '$hours h';
  return '${hours}h ${mins}m';
}

Future<void> showTripCompletionSheet(
  BuildContext context,
  TripStats stats,
) async {
  HapticFeedback.mediumImpact();
  await Future.delayed(const Duration(milliseconds: 90));
  HapticFeedback.lightImpact();

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: false,
    builder: (ctx) => _TripCompletionSheet(stats: stats),
  );
}

class _TripCompletionSheet extends StatelessWidget {
  final TripStats stats;
  const _TripCompletionSheet({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = stats.perPerson.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  stats.firstOfDay ? Icons.auto_awesome : Icons.check_circle,
                  color: stats.firstOfDay
                      ? Colors.amber.shade600
                      : theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stats.firstOfDay ? 'Trip done — first of the day' : 'Trip done',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                  label: 'Items',
                  value: stats.itemCount.toString(),
                ),
                const SizedBox(width: 24),
                _Stat(
                  label: 'Duration',
                  value: formatTripDuration(stats.duration),
                ),
              ],
            ),
            if (sorted.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Who bought what', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              ...sorted.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key)),
                      Text(
                        '${e.value}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  key: const ValueKey('trip-sheet-wallet'),
                  icon: const Icon(Icons.wallet),
                  label: const Text('Open Wallet'),
                  onPressed: openGoogleWallet,
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Nice'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
