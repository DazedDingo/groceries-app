import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UnitSystem { metric, us }

final unitSystemProvider = StateNotifierProvider<UnitSystemNotifier, UnitSystem>((ref) {
  return UnitSystemNotifier();
});

class UnitSystemNotifier extends StateNotifier<UnitSystem> {
  UnitSystemNotifier() : super(UnitSystem.metric) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('unitSystem');
    if (val == 'us') state = UnitSystem.us;
  }

  Future<void> toggle() async {
    state = state == UnitSystem.metric ? UnitSystem.us : UnitSystem.metric;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('unitSystem', state == UnitSystem.us ? 'us' : 'metric');
  }
}

/// Metric ↔ US conversion pairs.
const _conversions = <String, _Conversion>{
  // Weight
  'g':   _Conversion(usUnit: 'oz',    factor: 0.035274),
  'kg':  _Conversion(usUnit: 'lb',    factor: 2.20462),
  'oz':  _Conversion(usUnit: 'oz',    factor: 1),       // already US
  'lb':  _Conversion(usUnit: 'lb',    factor: 1),       // already US
  // Volume
  'ml':  _Conversion(usUnit: 'fl oz', factor: 0.033814),
  'L':   _Conversion(usUnit: 'gal',   factor: 0.264172),
  'cups': _Conversion(usUnit: 'cups', factor: 1),       // same
};

// Reverse: US → metric
const _reverseConversions = <String, _Conversion>{
  'oz':    _Conversion(usUnit: 'g',  factor: 28.3495),
  'lb':    _Conversion(usUnit: 'kg', factor: 0.453592),
  'fl oz': _Conversion(usUnit: 'ml', factor: 29.5735),
  'gal':   _Conversion(usUnit: 'L',  factor: 3.78541),
};

class _Conversion {
  final String usUnit;
  final double factor;
  const _Conversion({required this.usUnit, required this.factor});
}

/// Format a quantity + unit for display, converting if needed.
/// Returns e.g. "300 g" or "10.6 oz" depending on the unit system.
String formatQuantityUnit(int quantity, String? unit, UnitSystem system) {
  if (unit == null || unit.isEmpty) return quantity > 1 ? '×$quantity' : '';

  if (system == UnitSystem.us) {
    final conv = _conversions[unit];
    if (conv != null && conv.factor != 1) {
      final converted = quantity * conv.factor;
      final display = converted == converted.roundToDouble()
          ? converted.round().toString()
          : converted.toStringAsFixed(1);
      return '$display ${conv.usUnit}';
    }
  } else if (system == UnitSystem.metric) {
    // If the stored unit is US, convert back to metric
    final conv = _reverseConversions[unit];
    if (conv != null) {
      final converted = quantity * conv.factor;
      final display = converted == converted.roundToDouble()
          ? converted.round().toString()
          : converted.toStringAsFixed(1);
      return '$display ${conv.usUnit}';
    }
  }

  return '$quantity $unit';
}
