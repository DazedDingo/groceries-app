import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/price_product.dart';
import 'costco_parser.dart';
import 'price_fetch_exception.dart';

/// Searches Costco UK for products matching a free-text term.
abstract class CostcoSearch {
  Future<List<PriceProduct>> search(String term);
}

const String _chromeUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

/// Costco's own "cartGroup" facet that restricts results to home-delivery
/// products.
const String _cartGroup = '8796093380189';

/// Plain-HTTP Costco UK search (no login or cookies needed).
class CostcoClient implements CostcoSearch {
  final http.Client _http;
  final bool _ownsClient;
  final Duration timeout;
  final DateTime Function() _clock;

  CostcoClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? DateTime.now;

  /// Builds the search URL for [term].
  static Uri searchUri(String term) {
    final q = Uri.encodeComponent(
      '${term.trim()}:relevance:cartGroup:$_cartGroup',
    );
    return Uri.parse(
      'https://www.costco.co.uk/rest/v2/uk/products/search'
      '?query=$q&pageSize=24&fields=FULL&lang=en_GB&curr=GBP',
    );
  }

  @override
  Future<List<PriceProduct>> search(String term) async {
    final http.Response res;
    try {
      res = await _http
          .get(
            searchUri(term),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _chromeUserAgent,
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const PriceFetchException(
        PriceStore.costco,
        "Costco didn't respond in time",
      );
    } catch (e) {
      throw PriceFetchException(PriceStore.costco, 'Costco request failed: $e');
    }
    if (res.statusCode != 200) {
      throw PriceFetchException(
        PriceStore.costco,
        'Costco returned HTTP ${res.statusCode}',
      );
    }
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map) throw const FormatException('not an object');
      return parseCostcoSearch(
        Map<String, dynamic>.from(json),
        fetchedAt: _clock(),
      );
    } on FormatException {
      throw const PriceFetchException(
        PriceStore.costco,
        'Costco sent a response we could not read',
      );
    }
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
