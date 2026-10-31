import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/price/promo_parser.dart';

void main() {
  group('parseMultiBuy', () {
    test('Any 2 for £1.20', () {
      expect(parseMultiBuy('Any 2 for £1.20'), const MultiBuy(2, 1.2));
    });
    test('2 for £5', () {
      expect(parseMultiBuy('2 for £5'), const MultiBuy(2, 5));
    });
    test('Any 5 for £5', () {
      expect(parseMultiBuy('Any 5 for £5'), const MultiBuy(5, 5));
    });
    test('Any 2 for £15', () {
      expect(parseMultiBuy('Any 2 for £15'), const MultiBuy(2, 15));
    });
    test('3 for 2', () {
      expect(parseMultiBuy('3 for 2'), const MultiBuy.nForM(3, 2));
    });
    test('2 for 90p', () {
      final mb = parseMultiBuy('2 for 90p')!;
      expect(mb.quantity, 2);
      expect(mb.total, closeTo(0.9, 1e-9));
    });
    test('case and spacing', () {
      expect(parseMultiBuy('  any 3 FOR £1.80 '), const MultiBuy(3, 1.8));
    });
    test('unknown promos give null', () {
      expect(parseMultiBuy('Buy 1 get 1 free'), isNull);
      expect(parseMultiBuy('Save 50p'), isNull);
      expect(parseMultiBuy('Clubcard price'), isNull);
      expect(parseMultiBuy(''), isNull);
      expect(parseMultiBuy('1 for £2'), isNull);
      expect(parseMultiBuy('2 for 3'), isNull); // not a "pay for fewer" deal
      expect(parseMultiBuy('3 for 1.5'), isNull);
    });
  });

  group('effectiveCost', () {
    test('no multibuy -> unit x qty', () {
      expect(effectiveCost(0.75, 3, null), closeTo(2.25, 1e-9));
    });
    test('qty below group size -> unit price', () {
      expect(
        effectiveCost(0.75, 1, const MultiBuy(2, 1.2)),
        closeTo(0.75, 1e-9),
      );
    });
    test('full groups plus remainder', () {
      // 5 items, 2 for £1.20: 2 groups (2.40) + 1 at 0.75
      expect(
        effectiveCost(0.75, 5, const MultiBuy(2, 1.2)),
        closeTo(3.15, 1e-9),
      );
    });
    test('exact groups', () {
      expect(effectiveCost(1.0, 5, const MultiBuy(5, 5)), closeTo(5, 1e-9));
      expect(effectiveCost(9.0, 4, const MultiBuy(2, 15)), closeTo(30, 1e-9));
    });
    test('3 for 2', () {
      // 7 items at £1: 2 groups at £2 + 1 at £1
      expect(
        effectiveCost(1.0, 7, const MultiBuy.nForM(3, 2)),
        closeTo(5, 1e-9),
      );
    });
    test('deal worse than singles is ignored', () {
      expect(effectiveCost(1.0, 2, const MultiBuy(2, 5)), closeTo(2, 1e-9));
    });
    test('zero qty', () {
      expect(effectiveCost(1.0, 0, const MultiBuy(2, 1)), 0);
    });
  });
}
