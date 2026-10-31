import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../models/price_product.dart';
import '../../screens/settings/price_lab_js.dart';
import 'asda_parser.dart';
import 'price_fetch_exception.dart';

/// Searches Asda groceries for products matching a free-text term.
abstract class AsdaSearch {
  Future<List<PriceProduct>> search(String term);

  /// Releases any platform resources. A later [search] may recreate them.
  Future<void> dispose();
}

const String _asdaSearchBase = 'https://www.asda.com/groceries/search/';

const String asdaTimeoutMessage =
    "Asda didn't respond — open Settings › Price lab once, then retry";

/// Finds the Algolia product-search response among the entries captured by
/// the Price lab fetch/XHR hook (`window.__priceLabNet`).
///
/// An entry is `{url, status, body}` where body is the raw response text. The
/// newest entry whose url contains `/1/indexes/`, whose status is 200 (or
/// absent) and whose body is JSON containing an `ASDA_PRODUCTS` result wins.
/// Returns the decoded body, or null when nothing matches. Never throws.
Map<String, dynamic>? findAsdaAlgoliaResponse(List<dynamic> captured) {
  for (final entry in captured.reversed) {
    if (entry is! Map) continue;
    final url = entry['url'];
    if (url is! String || !url.contains('/1/indexes/')) continue;
    final status = entry['status'];
    if (status is num && status != 200) continue;
    final body = entry['body'];
    dynamic json;
    try {
      json = body is String ? jsonDecode(body) : body;
    } catch (_) {
      continue;
    }
    if (json is! Map) continue;
    final results = json['results'];
    if (results is! List) continue;
    final hasAsda = results.any(
      (r) => r is Map && r['index'] == 'ASDA_PRODUCTS',
    );
    if (!hasAsda) continue;
    return Map<String, dynamic>.from(json);
  }
  return null;
}

/// Polls [readCaptured] until an Asda Algolia response shows up, returning it,
/// or null on timeout.
///
/// Waits [baseTimeout]; if [readTitle] ever reports a Cloudflare interstitial
/// ("Just a moment") the deadline stretches to [challengeTimeout] (measured
/// from the start). Time and sleeping are injectable for tests.
Future<Map<String, dynamic>?> pollForAsdaResponse({
  required Future<List<dynamic>> Function() readCaptured,
  required Future<String?> Function() readTitle,
  Duration interval = const Duration(milliseconds: 250),
  Duration baseTimeout = const Duration(seconds: 20),
  Duration challengeTimeout = const Duration(seconds: 30),
  DateTime Function()? now,
  Future<void> Function(Duration)? sleep,
}) async {
  final clock = now ?? DateTime.now;
  final wait = sleep ?? (Duration d) => Future<void>.delayed(d);
  final start = clock();
  var limit = baseTimeout;
  while (true) {
    final found = findAsdaAlgoliaResponse(await readCaptured());
    if (found != null) return found;
    final title = await readTitle();
    if (title != null && title.contains('Just a moment')) {
      limit = challengeTimeout;
    }
    if (clock().difference(start) >= limit) return null;
    await wait(interval);
  }
}

/// Asda search through a hidden WebView (plain HTTP is Cloudflare-blocked).
///
/// The headless WebView is created on first use and reused. Searches run one
/// at a time. Cookies are shared with the Price lab WebView, so a challenge
/// passed there carries over.
class AsdaWebClient implements AsdaSearch {
  AsdaWebClient({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  HeadlessInAppWebView? _headless;
  Future<InAppWebViewController>? _controller;
  Future<void> _tail = Future<void>.value();

  @override
  Future<List<PriceProduct>> search(String term) {
    final result = _tail.then((_) => _searchNow(term));
    // Keep the queue alive after a failure.
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<InAppWebViewController> _ensure() {
    return _controller ??= _create().catchError((Object e) {
      _controller = null;
      throw e;
    });
  }

  Future<InAppWebViewController> _create() async {
    final ready = Completer<InAppWebViewController>();
    final headless = HeadlessInAppWebView(
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: priceLabHookJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
      ),
      onWebViewCreated: (c) {
        if (!ready.isCompleted) ready.complete(c);
      },
    );
    _headless = headless;
    await headless.run();
    return ready.future.timeout(const Duration(seconds: 10));
  }

  Future<List<PriceProduct>> _searchNow(String term) async {
    final InAppWebViewController web;
    try {
      web = await _ensure();
    } catch (e) {
      debugPrint('AsdaWebClient: could not start WebView: $e');
      await dispose();
      throw const PriceFetchException(PriceStore.asda, asdaTimeoutMessage);
    }

    Future<List<dynamic>> readCaptured() async {
      try {
        final raw = await web.evaluateJavascript(
          source: 'JSON.stringify(window.__priceLabNet || [])',
        );
        final decoded = raw is String ? jsonDecode(raw) : raw;
        return decoded is List ? decoded : const [];
      } catch (_) {
        // Mid-navigation the JS context can be unavailable; keep polling.
        return const [];
      }
    }

    Future<String?> readTitle() async {
      try {
        return await web.getTitle();
      } catch (_) {
        return null;
      }
    }

    try {
      await web.evaluateJavascript(source: 'window.__priceLabNet = [];');
      await web.loadUrl(
        urlRequest: URLRequest(
          url: WebUri('$_asdaSearchBase${Uri.encodeComponent(term.trim())}'),
        ),
      );
    } catch (e) {
      debugPrint('AsdaWebClient: load failed: $e');
      throw const PriceFetchException(PriceStore.asda, asdaTimeoutMessage);
    }

    final json = await pollForAsdaResponse(
      readCaptured: readCaptured,
      readTitle: readTitle,
    );
    if (json == null) {
      throw const PriceFetchException(PriceStore.asda, asdaTimeoutMessage);
    }
    return parseAsdaAlgolia(json, fetchedAt: _clock());
  }

  @override
  Future<void> dispose() async {
    final h = _headless;
    _headless = null;
    _controller = null;
    try {
      await h?.dispose();
    } catch (e) {
      debugPrint('AsdaWebClient: dispose failed: $e');
    }
  }
}
