import 'dart:convert';

/// Max characters of page HTML kept in a dump page.
const int priceLabMaxHtmlChars = 400000;

/// One captured page in a Price lab dump.
class PriceLabPage {
  PriceLabPage({
    required this.url,
    this.term,
    this.title,
    this.loggedInHint,
    this.extracted = const [],
    this.network = const [],
    this.html = '',
    this.globals = const [],
  });

  final String? term;
  final String url;
  final String? title;
  final bool? loggedInHint;
  final List<dynamic> extracted;
  final List<dynamic> network;
  final String html;
  final List<String> globals;

  /// Builds a page from the JSON string returned by the JS snapshot function.
  /// Tolerant of null / garbage: returns a page with empty fields.
  factory PriceLabPage.fromSnapshot({
    required String url,
    String? term,
    String? snapshotJson,
  }) {
    Map<String, dynamic> m = {};
    try {
      final d = snapshotJson == null ? null : jsonDecode(snapshotJson);
      if (d is Map) m = Map<String, dynamic>.from(d);
    } catch (_) {}
    return PriceLabPage(
      term: term,
      url: url,
      title: m['title']?.toString(),
      loggedInHint: m['loggedInHint'] is bool ? m['loggedInHint'] as bool : null,
      extracted: m['extracted'] is List ? m['extracted'] as List : const [],
      network: m['network'] is List ? m['network'] as List : const [],
      html: m['html']?.toString() ?? '',
      globals: m['globals'] is List
          ? [for (final g in m['globals'] as List) g.toString()]
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'term': term,
        'url': url,
        'title': title,
        'loggedInHint': loggedInHint,
        'extracted': extracted,
        'network': network,
        'html': html.length > priceLabMaxHtmlChars
            ? html.substring(0, priceLabMaxHtmlChars)
            : html,
        'globals': globals,
      };
}

/// Builds the shareable dump map. Pure: no WebView needed.
Map<String, dynamic> buildPriceLabDump({
  required DateTime generatedAt,
  required String appVersion,
  required String userAgent,
  required List<PriceLabPage> pages,
}) =>
    {
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'appVersion': appVersion,
      'userAgent': userAgent,
      'pages': [for (final p in pages) p.toJson()],
    };

/// asda_dump_<yyyyMMdd_HHmm>.json (local time).
String priceLabDumpFilename(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'asda_dump_${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
      '_${two(t.hour)}${two(t.minute)}.json';
}
