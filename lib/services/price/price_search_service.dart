import 'dart:async';
import 'dart:collection';

import '../../models/item.dart';
import '../../models/price_link.dart';
import '../../models/price_product.dart';
import 'asda_client.dart';
import 'auto_match.dart';
import 'costco_client.dart';
import 'price_compare.dart';
import 'price_fetch_exception.dart';

enum PriceRunPhase { searching, comparing, done }

/// Everything a finished comparison run produced.
class PriceRunResult {
  final CompareResult result;

  /// The auto-matcher's pick for every list item (by item key), whether or
  /// not the user has confirmed a link for it. Lets the UI show "suggested"
  /// and lets a reset fall back without re-fetching.
  final Map<String, AutoMatchResult> auto;

  /// A store that failed for every item it was asked about, with a
  /// user-presentable reason. That store counts as having no results.
  final Map<PriceStore, String> storeErrors;

  /// The link actually compared for each item: the refreshed confirmed link
  /// if there is one, else the auto-match.
  final Map<String, PriceLink> effectiveLinks;
  final PriceFees fees;

  const PriceRunResult({
    required this.result,
    required this.auto,
    required this.storeErrors,
    required this.effectiveLinks,
    required this.fees,
  });
}

class PriceRunProgress {
  final int done;
  final int total;
  final String? currentItem;
  final PriceRunPhase phase;

  /// Only set on the final event ([phase] == [PriceRunPhase.done]).
  final PriceRunResult? result;

  /// Stores whose circuit breaker has tripped so far this run (so the UI can
  /// warn before the run finishes). The final result's map is the full set.
  final Map<PriceStore, String> storeErrors;

  const PriceRunProgress({
    required this.done,
    required this.total,
    this.currentItem,
    required this.phase,
    this.result,
    this.storeErrors = const {},
  });
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// A search skipped because the store's circuit breaker is open.
class _BreakerOpen implements Exception {
  final String message;
  const _BreakerOpen(this.message);
}

String _errorMessage(Object e) => switch (e) {
  PriceFetchException() => e.message,
  _BreakerOpen() => e.message,
  _ => e.toString(),
};

/// Per-run circuit breaker: after [threshold] consecutive failures for a
/// store, further searches to it are skipped for the rest of the run. A
/// success resets the count.
class _Breaker {
  final Map<PriceStore, int> threshold;
  final Map<PriceStore, int> _consecutive = {
    PriceStore.asda: 0,
    PriceStore.costco: 0,
  };
  final Map<PriceStore, String> tripped = {};
  _Breaker(this.threshold);

  void success(PriceStore s) => _consecutive[s] = 0;

  void failure(PriceStore s, Object e) {
    final n = (_consecutive[s] ?? 0) + 1;
    _consecutive[s] = n;
    if (n >= threshold[s]! && !tripped.containsKey(s)) {
      tripped[s] = _errorMessage(e);
    }
  }
}

/// Limits how many async operations run at once, in FIFO order.
class _Gate {
  int _free;
  final Queue<Completer<void>> _waiting = Queue();
  _Gate(this._free);

  Future<T> run<T>(Future<T> Function() f) async {
    if (_free > 0) {
      _free--;
    } else {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    try {
      return await f();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _free++;
      }
    }
  }
}

class _CacheEntry {
  final Future<List<PriceProduct>> future;
  final DateTime at;
  _CacheEntry(this.future, this.at);
}

class _Want {
  final String key;
  final String name;
  int qty;
  _Want(this.key, this.name, this.qty);
}

class _Outcome {
  final List<PriceProduct>? products;
  final Object? error;
  final bool skipped;
  const _Outcome.ok(List<PriceProduct> this.products)
    : error = null,
      skipped = false;
  const _Outcome.failed(Object this.error) : products = null, skipped = false;
  const _Outcome.skipped() : products = null, error = null, skipped = true;
  bool get ok => products != null;
}

class _Stats {
  int attempts = 0;
  int failures = 0;
  String? lastError;
}

/// Runs the live price comparison for a shopping list: searches both stores
/// per item (cached), matches or refreshes products, and compares the basket.
class PriceSearchService {
  PriceSearchService({
    required this.asda,
    required this.costco,
    this.cacheTtl = const Duration(hours: 6),
    this.asdaBreakerThreshold = 2,
    this.costcoBreakerThreshold = 3,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AsdaSearch asda;
  final CostcoSearch costco;
  final Duration cacheTtl;

  /// Consecutive failures after which a store is skipped for the rest of a
  /// run (a success resets the count).
  final int asdaBreakerThreshold;
  final int costcoBreakerThreshold;
  final DateTime Function() _clock;

  final Map<String, _CacheEntry> _cache = {};
  // Asda runs one search at a time (single WebView); Costco up to 3.
  final _Gate _asdaGate = _Gate(1);
  final _Gate _costcoGate = _Gate(3);

  /// How many items ahead of the one being processed may already be searching.
  static const int _lookahead = 3;

  /// Searches one store for [term], through the TTL cache. Throws
  /// [PriceFetchException] on failure (failures are not cached).
  Future<List<PriceProduct>> searchStore(PriceStore store, String term) =>
      _search(store, term);

  Future<List<PriceProduct>> _search(
    PriceStore store,
    String term, {
    bool Function()? isCancelled,
    _Breaker? breaker,
  }) {
    final key = '${store.value}|${PriceLink.keyFor(term)}';
    final now = _clock();
    final hit = _cache[key];
    if (hit != null && now.difference(hit.at) < cacheTtl) return hit.future;

    final gate = store == PriceStore.asda ? _asdaGate : _costcoGate;
    final f = gate.run(() async {
      if (isCancelled?.call() ?? false) throw const _Cancelled();
      final open = breaker?.tripped[store];
      if (open != null) throw _BreakerOpen(open);
      try {
        final r = store == PriceStore.asda
            ? await asda.search(term)
            : await costco.search(term);
        breaker?.success(store);
        return r;
      } catch (e) {
        breaker?.failure(store, e);
        rethrow;
      }
    });
    final entry = _CacheEntry(f, now);
    _cache[key] = entry;
    f.then(
      (_) {},
      onError: (Object _) {
        if (identical(_cache[key], entry)) _cache.remove(key);
      },
    );
    return f;
  }

  /// Runs a comparison. Closing the subscription stops further searches.
  Stream<PriceRunProgress> run({
    required List<ShoppingItem> items,
    required Map<String, PriceLink> confirmed,
    required PriceFees fees,
  }) {
    var cancelled = false;
    final cancelSignal = Completer<void>();
    late final StreamController<PriceRunProgress> ctrl;
    ctrl = StreamController<PriceRunProgress>(
      onListen: () {
        unawaited(() async {
          try {
            await _execute(
              items,
              confirmed,
              fees,
              emit: (p) {
                if (!cancelled && !ctrl.isClosed) ctrl.add(p);
              },
              isCancelled: () => cancelled,
              cancelSignal: cancelSignal.future,
            );
          } catch (e, st) {
            if (!cancelled && !ctrl.isClosed) ctrl.addError(e, st);
          } finally {
            if (!ctrl.isClosed) await ctrl.close();
          }
        }());
      },
      onCancel: () {
        cancelled = true;
        if (!cancelSignal.isCompleted) cancelSignal.complete();
      },
    );
    return ctrl.stream;
  }

  List<_Want> _dedupe(List<ShoppingItem> items) {
    final byKey = <String, _Want>{};
    for (final it in items) {
      final key = PriceLink.keyFor(it.name);
      if (key.isEmpty) continue;
      final qty = it.quantity < 1 ? 1 : it.quantity;
      final w = byKey[key];
      if (w == null) {
        byKey[key] = _Want(key, it.name.trim(), qty);
      } else {
        w.qty += qty;
      }
    }
    return byKey.values.toList();
  }

  Future<void> _execute(
    List<ShoppingItem> items,
    Map<String, PriceLink> confirmed,
    PriceFees fees, {
    required void Function(PriceRunProgress) emit,
    required bool Function() isCancelled,
    required Future<void> cancelSignal,
  }) async {
    final wants = _dedupe(items);
    final total = wants.length;
    final stats = {PriceStore.asda: _Stats(), PriceStore.costco: _Stats()};
    final breaker = _Breaker({
      PriceStore.asda: asdaBreakerThreshold,
      PriceStore.costco: costcoBreakerThreshold,
    });

    Future<T?> orCancel<T>(Future<T> f) =>
        Future.any<T?>([f, cancelSignal.then<T?>((_) => null)]);

    Future<_Outcome> attempt(PriceStore store, String term) async {
      try {
        return _Outcome.ok(
          await _search(
            store,
            term,
            isCancelled: isCancelled,
            breaker: breaker,
          ),
        );
      } catch (e) {
        return _Outcome.failed(e);
      }
    }

    // Starts both store searches for one item (skipping a store the user has
    // marked unavailable on a confirmed link).
    final started = <int, ({Future<_Outcome> asda, Future<_Outcome> costco})>{};
    void startUpTo(int i) {
      for (var j = 0; j <= i && j < total; j++) {
        started.putIfAbsent(j, () {
          final w = wants[j];
          final link = confirmed[w.key];
          return (
            asda: (link?.asdaUnavailable ?? false)
                ? Future.value(const _Outcome.skipped())
                : attempt(PriceStore.asda, w.name),
            costco: (link?.costcoUnavailable ?? false)
                ? Future.value(const _Outcome.skipped())
                : attempt(PriceStore.costco, w.name),
          );
        });
      }
    }

    void record(PriceStore store, _Outcome o) {
      if (o.skipped || o.error is _Cancelled || o.error is _BreakerOpen) return;
      final s = stats[store]!;
      s.attempts++;
      if (!o.ok) {
        s.failures++;
        final e = o.error;
        s.lastError = _errorMessage(e!);
      }
    }

    final auto = <String, AutoMatchResult>{};
    final effective = <String, PriceLink>{};
    final lines = <CompareLine>[];

    for (var i = 0; i < total; i++) {
      if (isCancelled()) return;
      final w = wants[i];
      emit(
        PriceRunProgress(
          done: i,
          total: total,
          currentItem: w.name,
          phase: PriceRunPhase.searching,
          storeErrors: Map.of(breaker.tripped),
        ),
      );
      startUpTo(i + _lookahead);
      final s = started[i]!;
      final both = await orCancel(Future.wait([s.asda, s.costco]));
      if (both == null || isCancelled()) return;
      final a = both[0];
      final c = both[1];
      record(PriceStore.asda, a);
      record(PriceStore.costco, c);

      final am = autoMatch(
        w.name,
        asda: a.products ?? const [],
        costco: c.products ?? const [],
        now: _clock(),
      );
      auto[w.key] = am;

      final stored = confirmed[w.key];
      PriceLink link;
      if (stored == null) {
        link = am.link;
      } else {
        final asdaList = await orCancel(
          _refresh(
            PriceStore.asda,
            stored.asda,
            a,
            attempt,
            stored.asdaUnavailable,
          ),
        );
        final costcoList = await orCancel(
          _refresh(
            PriceStore.costco,
            stored.costco,
            c,
            attempt,
            stored.costcoUnavailable,
          ),
        );
        if (asdaList == null || costcoList == null || isCancelled()) return;
        link = PriceLink(
          itemKey: stored.itemKey,
          mode: stored.mode,
          asda: asdaList,
          costco: costcoList,
          asdaUnavailable: stored.asdaUnavailable,
          costcoUnavailable: stored.costcoUnavailable,
          userConfirmed: true,
          updatedAt: stored.updatedAt,
        );
      }
      effective[w.key] = link;
      lines.add(CompareLine(itemName: w.name, qty: w.qty, link: link));
    }

    emit(
      PriceRunProgress(
        done: total,
        total: total,
        phase: PriceRunPhase.comparing,
        storeErrors: Map.of(breaker.tripped),
      ),
    );
    final storeErrors = <PriceStore, String>{...breaker.tripped};
    stats.forEach((store, s) {
      if (s.attempts > 0 && s.failures == s.attempts) {
        storeErrors.putIfAbsent(store, () => s.lastError ?? 'Search failed');
      }
    });
    final result = compareBasket(lines, fees: fees);
    emit(
      PriceRunProgress(
        done: total,
        total: total,
        phase: PriceRunPhase.done,
        storeErrors: storeErrors,
        result: PriceRunResult(
          result: result,
          auto: auto,
          storeErrors: storeErrors,
          effectiveLinks: effective,
          fees: fees,
        ),
      ),
    );
  }

  /// Refreshes confirmed [stored] products from the item search [primary],
  /// falling back to one search per product name. Products that can't be
  /// found keep their last-known data, flagged stale.
  Future<List<PriceProduct>> _refresh(
    PriceStore store,
    List<PriceProduct> stored,
    _Outcome primary,
    Future<_Outcome> Function(PriceStore, String) attempt,
    bool unavailable,
  ) async {
    if (unavailable || stored.isEmpty) return stored;
    PriceProduct? byId(List<PriceProduct>? l, String id) {
      for (final p in l ?? const <PriceProduct>[]) {
        if (p.id == id) return p;
      }
      return null;
    }

    final out = <PriceProduct>[];
    for (final p in stored) {
      var found = byId(primary.products, p.id);
      // Only worth an extra search when the store itself is answering.
      if (found == null && primary.ok) {
        final extra = await attempt(store, p.name);
        found = byId(extra.products, p.id);
      }
      out.add(found ?? p.withStale(true));
    }
    return out;
  }
}
