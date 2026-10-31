import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/price_lab_hit.dart';
import '../../services/price_lab_dump.dart';
import 'price_lab_js.dart';

const _homeUrl = 'https://www.asda.com/groceries';
const _searchBase = 'https://www.asda.com/groceries/search/';

/// Search terms used by the "Batch test" button.
const priceLabBatchTerms = <String>[
  'milk',
  'basmati rice',
  'toilet roll',
  'kitchen roll',
  'spaghetti',
  'baked beans',
  'chopped tomatoes',
  'tea bags',
  'olive oil',
  'laundry liquid',
  'dishwasher tablets',
  'cereal',
];

String priceLabSearchUrl(String term) =>
    '$_searchBase${Uri.encodeComponent(term.trim())}';

/// Hidden debug screen (unlocked by tapping the version line 7 times in
/// Settings). Hosts an Asda WebView so the user can log in once, then runs
/// heuristic price extraction and builds a raw dump to share for designing a
/// real extractor.
class PriceLabScreen extends StatefulWidget {
  const PriceLabScreen({super.key});

  @override
  State<PriceLabScreen> createState() => _PriceLabScreenState();
}

class _PriceLabScreenState extends State<PriceLabScreen> {
  InAppWebViewController? _web;
  final _termCtrl = TextEditingController();
  final List<PriceLabPage> _pages = [];

  Completer<void>? _loadDone;
  String _currentUrl = _homeUrl;
  int _progress = 0;

  bool _batchRunning = false;
  bool _cancelBatch = false;
  String? _batchStatus;
  double? _batchFraction;

  @override
  void dispose() {
    _cancelBatch = true;
    _termCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _go() async {
    final term = _termCtrl.text.trim();
    if (term.isEmpty) return;
    FocusScope.of(context).unfocus();
    await _web?.loadUrl(
        urlRequest: URLRequest(url: WebUri(priceLabSearchUrl(term))));
  }

  /// Installs the extractor functions into the current page and returns the
  /// snapshot JSON string (or null on failure).
  Future<String?> _snapshot() async {
    final web = _web;
    if (web == null) return null;
    try {
      await web.evaluateJavascript(source: priceLabExtractorJs);
      final res = await web.evaluateJavascript(
          source: 'window.__priceLabSnapshot()');
      return res is String ? res : null;
    } catch (e) {
      debugPrint('PriceLab snapshot failed: $e');
      return null;
    }
  }

  String? _termFromUrl(String url) {
    final i = url.indexOf('/search/');
    if (i < 0) return null;
    var rest = url.substring(i + '/search/'.length);
    rest = rest.split(RegExp(r'[?#]')).first;
    try {
      return Uri.decodeComponent(rest);
    } catch (_) {
      return rest;
    }
  }

  Future<PriceLabPage?> _capture({String? term}) async {
    final web = _web;
    if (web == null) return null;
    final url = (await web.getUrl())?.toString() ?? _currentUrl;
    final json = await _snapshot();
    final page = PriceLabPage.fromSnapshot(
      url: url,
      term: term ?? _termFromUrl(url),
      snapshotJson: json,
    );
    _pages.removeWhere((p) => p.url == page.url);
    _pages.add(page);
    return page;
  }

  Future<void> _extract() async {
    final page = await _capture();
    if (!mounted) return;
    if (page == null) {
      _toast('WebView not ready');
      return;
    }
    final hits = PriceLabHit.listFromJson(page.extracted);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => _HitsList(
          hits: hits,
          scroll: scroll,
          networkCount: page.network.length,
        ),
      ),
    );
  }

  Future<void> _waitForLoad() async {
    final c = _loadDone = Completer<void>();
    await c.future.timeout(const Duration(seconds: 30), onTimeout: () {});
  }

  Future<void> _batch() async {
    if (_batchRunning || _web == null) return;
    setState(() {
      _batchRunning = true;
      _cancelBatch = false;
      _batchFraction = 0;
      _batchStatus = 'Starting…';
    });
    var done = 0;
    try {
      for (final term in priceLabBatchTerms) {
        if (_cancelBatch || !mounted) break;
        setState(() => _batchStatus =
            '${done + 1}/${priceLabBatchTerms.length}: $term');
        final wait = _waitForLoad();
        await _web!.loadUrl(
            urlRequest: URLRequest(url: WebUri(priceLabSearchUrl(term))));
        await wait;
        if (_cancelBatch || !mounted) break;
        await Future<void>.delayed(const Duration(seconds: 3));
        if (_cancelBatch || !mounted) break;
        await _capture(term: term);
        done++;
        if (mounted) {
          setState(() => _batchFraction = done / priceLabBatchTerms.length);
        }
      }
    } catch (e) {
      _toast('Batch error: $e');
    } finally {
      if (mounted) {
        final cancelled = _cancelBatch;
        setState(() {
          _batchRunning = false;
          _batchFraction = null;
          _batchStatus = null;
        });
        _toast(cancelled
            ? 'Batch cancelled ($done captured)'
            : 'Batch done: $done pages captured');
      }
    }
  }

  Future<void> _shareDump() async {
    if (_pages.isEmpty) await _capture();
    if (_pages.isEmpty) {
      _toast('Nothing to share yet');
      return;
    }
    String ua = '';
    try {
      final r = await _web?.evaluateJavascript(source: 'navigator.userAgent');
      ua = r?.toString() ?? '';
    } catch (_) {}
    final info = await PackageInfo.fromPlatform();
    final now = DateTime.now();
    final dump = buildPriceLabDump(
      generatedAt: now,
      appVersion: '${info.version}+${info.buildNumber}',
      userAgent: ua,
      pages: _pages,
    );
    final bytes = utf8.encode(jsonEncode(dump));
    final name = priceLabDumpFilename(now);
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/json', name: name)],
      fileNameOverrides: [name],
      subject: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Price lab'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back (page)',
            onPressed: () => _web?.goBack(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => _web?.reload(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _termCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _go(),
                    decoration: const InputDecoration(
                      hintText: 'Search term',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _go, child: const Text('Go')),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_progress > 0 && _progress < 100)
            LinearProgressIndicator(value: _progress / 100, minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
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
              onWebViewCreated: (c) => _web = c,
              onProgressChanged: (_, p) {
                if (mounted) setState(() => _progress = p);
              },
              onLoadStop: (_, url) {
                _currentUrl = url?.toString() ?? _currentUrl;
                final c = _loadDone;
                if (c != null && !c.isCompleted) c.complete();
              },
              onReceivedError: (_, __, ___) {
                final c = _loadDone;
                if (c != null && !c.isCompleted) c.complete();
              },
            ),
          ),
          if (_batchRunning)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_batchStatus ?? '', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: _batchFraction),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _batchRunning ? null : _extract,
                      child: const Text('Extract'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _batchRunning
                        ? FilledButton.tonal(
                            onPressed: () => setState(() {
                              _cancelBatch = true;
                              _batchStatus = 'Cancelling…';
                            }),
                            child: const Text('Cancel'),
                          )
                        : OutlinedButton(
                            onPressed: _batch,
                            child: const Text('Batch test'),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _batchRunning ? null : _shareDump,
                      child: const Text('Share dump'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HitsList extends StatelessWidget {
  const _HitsList({
    required this.hits,
    required this.scroll,
    required this.networkCount,
  });

  final List<PriceLabHit> hits;
  final ScrollController scroll;
  final int networkCount;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          const Text('No products found on this page.'),
          const SizedBox(height: 8),
          Text('Captured JSON responses mentioning "price": $networkCount'),
          const SizedBox(height: 8),
          const Text('Use "Share dump" so the raw page can be inspected.'),
        ],
      );
    }
    return ListView.separated(
      controller: scroll,
      itemCount: hits.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                '${hits.length} items · $networkCount captured JSON responses'),
          );
        }
        final h = hits[i - 1];
        final price = h.price != null
            ? '£${h.price!.toStringAsFixed(2)}'
            : (h.priceText ?? '?');
        return ListTile(
          isThreeLine: true,
          title: Text(h.name ?? '(no name)'),
          trailing: Text(price,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text([
            if (h.unitPriceText != null) 'Unit: ${h.unitPriceText}',
            if (h.promoText != null) 'Promo: ${h.promoText}',
            '[${h.source ?? '?'}] ${h.url ?? ''}',
          ].join('\n')),
        );
      },
    );
  }
}
