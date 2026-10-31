/// Counts rapid taps and reports when [requiredTaps] land within [window].
///
/// Pure Dart (injectable clock) so the hidden "tap the version line 7 times"
/// gesture is unit-testable without a widget harness.
class TapUnlock {
  TapUnlock({
    this.requiredTaps = 7,
    this.window = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int requiredTaps;
  final Duration window;
  final DateTime Function() _clock;
  final List<DateTime> _taps = [];

  /// Registers a tap. Returns true exactly when this tap completes
  /// [requiredTaps] taps inside [window]; the counter then resets.
  bool tap() {
    final now = _clock();
    _taps.add(now);
    _taps.removeWhere((t) => now.difference(t) > window);
    if (_taps.length >= requiredTaps) {
      _taps.clear();
      return true;
    }
    return false;
  }

  void reset() => _taps.clear();
}
