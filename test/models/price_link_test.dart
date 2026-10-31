import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_link.dart';
import 'package:groceries_app/models/price_product.dart';

void main() {
  final t = DateTime.utc(2026, 10, 31, 9);

  PriceProduct product(PriceStore s, String id) => PriceProduct(
    store: s,
    id: id,
    brand: 'B',
    name: 'B Thing',
    price: 3.5,
    wasPrice: 4,
    offer: 'Rollback',
    promos: [
      PricePromo.parse(
        id: 'p',
        name: 'Any 2 for £6',
        endsAt: DateTime.utc(2027),
      ),
    ],
    storeUnitPriceText: '£3.50/KG',
    quantity: const PackQuantity(grams: 1000, count: 2, countUnit: 'bag'),
    inStock: false,
    shelf: 'Shelf',
    aisle: 'Aisle',
    dept: 'Dept',
    url: 'https://x/$id',
    fetchedAt: t,
  );

  test('keyFor lowercases, trims and collapses whitespace', () {
    expect(PriceLink.keyFor('  Olive   OIL \n'), 'olive oil');
    expect(PriceLink.keyFor('Tea'), 'tea');
    expect(PriceLink.keyFor(''), '');
  });

  test('PriceStore string ext', () {
    expect(PriceStore.asda.value, 'asda');
    expect(PriceStoreExt.fromString('costco'), PriceStore.costco);
    expect(PriceStoreExt.fromString('???'), PriceStore.asda);
  });

  test('LinkMode string ext', () {
    expect(LinkModeExt.fromString(LinkMode.anyOf.value), LinkMode.anyOf);
    expect(LinkModeExt.fromString(LinkMode.exact.value), LinkMode.exact);
    expect(LinkModeExt.fromString('junk'), LinkMode.exact);
  });

  test('PriceLink round trip keeps products, flags and mode', () {
    final link = PriceLink(
      itemKey: 'olive oil',
      mode: LinkMode.anyOf,
      asda: [product(PriceStore.asda, 'a1'), product(PriceStore.asda, 'a2')],
      costco: [product(PriceStore.costco, 'c1')],
      asdaUnavailable: false,
      costcoUnavailable: true,
      updatedAt: t,
    );
    final back = PriceLink.fromMap(link.toMap());
    expect(back.itemKey, 'olive oil');
    expect(back.mode, LinkMode.anyOf);
    expect(back.asda.map((p) => p.id), ['a1', 'a2']);
    expect(back.costco.single.id, 'c1');
    expect(back.costcoUnavailable, isTrue);
    expect(back.asdaUnavailable, isFalse);
    expect(back.updatedAt.toUtc(), t);
    expect(back.toMap(), link.toMap());
    final p = back.asda.first;
    expect(p.store, PriceStore.asda);
    expect(p.wasPrice, 4);
    expect(p.offer, 'Rollback');
    expect(p.inStock, isFalse);
    expect(p.shelf, 'Shelf');
    expect(p.aisle, 'Aisle');
    expect(p.dept, 'Dept');
    expect(
      p.quantity,
      const PackQuantity(grams: 1000, count: 2, countUnit: 'bag'),
    );
    expect(p.multiBuy!.quantity, 2);
    expect(p.promos.single.endsAt!.toUtc(), DateTime.utc(2027));
  });

  test('fromMap tolerates missing optional fields', () {
    final back = PriceLink.fromMap({'itemKey': 'x'});
    expect(back.asda, isEmpty);
    expect(back.costco, isEmpty);
    expect(back.mode, LinkMode.exact);
    expect(back.asdaUnavailable, isFalse);
    expect(back.userConfirmed, isFalse);
  });

  test('userConfirmed defaults to false and round trips', () {
    expect(PriceLink(itemKey: 'x', updatedAt: t).userConfirmed, isFalse);
    final link = PriceLink(itemKey: 'x', userConfirmed: true, updatedAt: t);
    expect(link.toMap()['userConfirmed'], isTrue);
    expect(PriceLink.fromMap(link.toMap()).userConfirmed, isTrue);
  });

  test('PricePromo without end date round trips', () {
    final p = PricePromo.parse(id: '1', name: 'Save 50p');
    final back = PricePromo.fromMap(p.toMap());
    expect(back.endsAt, isNull);
    expect(back.multiBuy, isNull);
    expect(back.name, 'Save 50p');
  });
}
