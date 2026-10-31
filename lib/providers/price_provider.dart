import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_link.dart';
import '../models/price_product.dart';
import '../services/price/asda_client.dart';
import '../services/price/costco_client.dart';
import '../services/price/price_compare.dart';
import '../services/price/price_links_service.dart';
import '../services/price/price_search_service.dart';
import 'household_provider.dart';
import 'items_provider.dart';

final costcoSearchProvider = Provider<CostcoSearch>((ref) {
  final client = CostcoClient();
  ref.onDispose(client.close);
  return client;
});

final asdaSearchProvider = Provider<AsdaSearch>((ref) {
  final client = AsdaWebClient();
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});

final priceLinksServiceProvider = Provider<PriceLinksService>(
  (ref) => PriceLinksService(),
);

/// The user-confirmed links, keyed by item key. Empty without a household.
final priceLinksProvider = StreamProvider<Map<String, PriceLink>>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return Stream.value(const <String, PriceLink>{});
  return ref.watch(priceLinksServiceProvider).linksStream(householdId);
});

/// Delivery fees (defaults when the household hasn't set any).
final priceFeesProvider = StreamProvider<PriceFees>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId == null) return Stream.value(const PriceFees());
  return ref.watch(priceLinksServiceProvider).settingsStream(householdId);
});

final priceSearchServiceProvider = Provider<PriceSearchService>((ref) {
  return PriceSearchService(
    asda: ref.watch(asdaSearchProvider),
    costco: ref.watch(costcoSearchProvider),
  );
});

class PriceCompareState {
  final bool running;
  final PriceRunProgress? progress;
  final PriceRunResult? last;
  final DateTime? lastRunAt;
  final String? error;

  const PriceCompareState({
    this.running = false,
    this.progress,
    this.last,
    this.lastRunAt,
    this.error,
  });

  PriceCompareState copyWith({
    bool? running,
    PriceRunProgress? progress,
    bool clearProgress = false,
    PriceRunResult? last,
    DateTime? lastRunAt,
    String? error,
    bool clearError = false,
  }) => PriceCompareState(
    running: running ?? this.running,
    progress: clearProgress ? null : (progress ?? this.progress),
    last: last ?? this.last,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Drives a price comparison and holds its latest result. Confirming or
/// resetting a match re-runs only the (pure) comparison on the held data, so
/// the user sees the effect immediately without new store searches.
class PriceCompareController extends StateNotifier<PriceCompareState> {
  PriceCompareController(this._ref, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const PriceCompareState());

  final Ref _ref;
  final DateTime Function() _clock;
  StreamSubscription<PriceRunProgress>? _sub;

  /// Fetches live prices for the current shopping list and compares.
  Future<void> compare() async {
    if (state.running) return;
    state = state.copyWith(
      running: true,
      clearProgress: true,
      clearError: true,
    );
    final done = Completer<void>();
    try {
      // Resolve the household first so the stream providers below build once
      // with the real id rather than being rebuilt mid-await.
      await _ref.read(householdIdProvider.future);
      final items = _ref.read(itemsProvider).valueOrNull ?? const [];
      final confirmed = await _ref.read(priceLinksProvider.future);
      final fees = await _ref.read(priceFeesProvider.future);
      final stream = _ref
          .read(priceSearchServiceProvider)
          .run(items: items, confirmed: confirmed, fees: fees);
      _sub = stream.listen(
        (p) {
          if (p.result != null) {
            state = state.copyWith(
              progress: p,
              last: p.result,
              lastRunAt: _clock(),
            );
          } else {
            state = state.copyWith(progress: p);
          }
        },
        onError: (Object e, StackTrace _) {
          state = state.copyWith(error: e.toString());
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
    } catch (e) {
      if (mounted) state = state.copyWith(error: e.toString());
    } finally {
      _sub = null;
      if (mounted) state = state.copyWith(running: false);
    }
  }

  /// Saves the user's choice for [itemKey] and recomputes the comparison from
  /// the last run's data, without re-fetching.
  Future<void> confirmMatch(
    String itemKey, {
    List<PriceProduct> asda = const [],
    List<PriceProduct> costco = const [],
    LinkMode mode = LinkMode.exact,
    bool asdaUnavailable = false,
    bool costcoUnavailable = false,
  }) async {
    final link = PriceLink(
      itemKey: itemKey,
      mode: mode,
      asda: asda,
      costco: costco,
      asdaUnavailable: asdaUnavailable,
      costcoUnavailable: costcoUnavailable,
      userConfirmed: true,
      updatedAt: _clock(),
    );
    try {
      final hid = await _ref.read(householdIdProvider.future);
      if (hid == null) throw StateError('No household');
      await _ref.read(priceLinksServiceProvider).saveLink(hid, link);
      await _applyLocally(itemKey, link);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Forgets the user's choice for [itemKey]; the comparison falls back to
  /// the auto-match from the last run (no re-fetch).
  Future<void> resetMatch(String itemKey) async {
    try {
      final hid = await _ref.read(householdIdProvider.future);
      if (hid == null) throw StateError('No household');
      await _ref.read(priceLinksServiceProvider).removeLink(hid, itemKey);
      await _applyLocally(itemKey, state.last?.auto[itemKey]?.link);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> _applyLocally(String itemKey, PriceLink? link) async {
    final last = state.last;
    if (last == null || !last.effectiveLinks.containsKey(itemKey)) return;
    final fees = _ref.read(priceFeesProvider).valueOrNull ?? last.fees;
    final effective = Map<String, PriceLink>.of(last.effectiveLinks);
    if (link == null) {
      effective.remove(itemKey);
    } else {
      effective[itemKey] = link;
    }
    final lines = [
      for (final l in last.result.lines)
        CompareLine(
          itemName: l.line.itemName,
          qty: l.line.qty,
          link: PriceLink.keyFor(l.line.itemName) == itemKey
              ? link
              : l.line.link,
        ),
    ];
    if (!mounted) return;
    state = state.copyWith(
      last: PriceRunResult(
        result: compareBasket(lines, fees: fees),
        auto: last.auto,
        storeErrors: last.storeErrors,
        effectiveLinks: effective,
        fees: fees,
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final priceCompareControllerProvider =
    StateNotifierProvider<PriceCompareController, PriceCompareState>(
      (ref) => PriceCompareController(ref),
    );
