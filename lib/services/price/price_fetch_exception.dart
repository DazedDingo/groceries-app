import '../../models/price_product.dart';

/// A store search failed (network error, non-200, timeout, Cloudflare...).
/// [message] is user-presentable.
class PriceFetchException implements Exception {
  final PriceStore store;
  final String message;
  const PriceFetchException(this.store, this.message);

  @override
  String toString() => 'PriceFetchException(${store.value}): $message';
}
