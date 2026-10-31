import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/tap_unlock.dart';

void main() {
  late DateTime now;
  late TapUnlock unlock;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    unlock = TapUnlock(clock: () => now);
  });

  bool tapAfter(Duration gap) {
    now = now.add(gap);
    return unlock.tap();
  }

  test('7 quick taps within the window unlock on the 7th', () {
    for (var i = 0; i < 6; i++) {
      expect(tapAfter(const Duration(milliseconds: 300)), isFalse);
    }
    expect(tapAfter(const Duration(milliseconds: 300)), isTrue);
  });

  test('fewer than 7 taps never unlock', () {
    for (var i = 0; i < 6; i++) {
      expect(tapAfter(const Duration(milliseconds: 100)), isFalse);
    }
  });

  test('slow taps (1s apart) never unlock', () {
    for (var i = 0; i < 20; i++) {
      expect(tapAfter(const Duration(seconds: 1)), isFalse);
    }
  });

  test('a long pause resets the count', () {
    for (var i = 0; i < 5; i++) {
      tapAfter(const Duration(milliseconds: 100));
    }
    // Pause beyond the window, then 6 more taps: still not enough.
    for (var i = 0; i < 6; i++) {
      expect(tapAfter(i == 0 ? const Duration(seconds: 5) : const Duration(milliseconds: 100)),
          isFalse);
    }
    expect(tapAfter(const Duration(milliseconds: 100)), isTrue);
  });

  test('counter resets after unlocking', () {
    for (var i = 0; i < 7; i++) {
      tapAfter(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 6; i++) {
      expect(tapAfter(const Duration(milliseconds: 100)), isFalse);
    }
    expect(tapAfter(const Duration(milliseconds: 100)), isTrue);
  });

  test('reset() clears pending taps', () {
    for (var i = 0; i < 6; i++) {
      tapAfter(const Duration(milliseconds: 100));
    }
    unlock.reset();
    expect(tapAfter(const Duration(milliseconds: 100)), isFalse);
  });
}
