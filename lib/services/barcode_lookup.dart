import 'dart:convert';
import 'package:http/http.dart' as http;

class BarcodeLookupResult {
  final String name;
  final String? brand;

  const BarcodeLookupResult({required this.name, this.brand});
}

class BarcodeLookupService {
  /// Look up a barcode using the Open Food Facts API.
  /// Returns null if the product is not found.
  Future<BarcodeLookupResult?> lookup(String barcode) async {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$barcode?fields=product_name,brands',
    );
    try {
      final response = await http.get(uri, headers: {
        'User-Agent': 'GroceriesApp/1.0 (Flutter)',
      });
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 1) return null;
      final product = data['product'] as Map<String, dynamic>?;
      if (product == null) return null;
      final name = product['product_name'] as String?;
      if (name == null || name.isEmpty) return null;
      return BarcodeLookupResult(
        name: name,
        brand: product['brands'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
