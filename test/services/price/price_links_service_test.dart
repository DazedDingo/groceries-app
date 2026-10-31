import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/price_link.dart';
import 'package:groceries_app/models/price_product.dart';
import 'package:groceries_app/services/price/price_compare.dart';
import 'package:groceries_app/services/price/price_links_service.dart';

final _t = DateTime.utc(2026, 10, 31, 12);

PriceProduct _p(PriceStore s, String id, double price, {bool stale = false}) =>
    PriceProduct(
      store: s,
      id: id,
      name: 'Product $id',
      price: price,
      fetchedAt: _t,
      stale: stale,
    );

PriceLink _link(String key, {String asdaId = 'a1', bool confirmed = false}) =>
    PriceLink(
      itemKey: key,
      asda: [_p(PriceStore.asda, asdaId, 1.5)],
      costco: [_p(PriceStore.costco, 'c1', 9.99, stale: true)],
      asdaUnavailable: false,
      costcoUnavailable: true,
      userConfirmed: confirmed,
      updatedAt: _t,
    );

void main() {
  late FakeFirebaseFirestore db;
  late PriceLinksService svc;

  setUp(() {
    db = FakeFirebaseFirestore();
    svc = PriceLinksService(db: db);
  });

  test('empty when nothing is stored', () async {
    expect(await svc.linksStream('h').first, isEmpty);
  });

  test('saveLink round-trips and forces userConfirmed', () async {
    await svc.saveLink('h', _link('milk'));
    final links = await svc.linksStream('h').first;
    expect(links.keys, ['milk']);
    final l = links['milk']!;
    expect(l.userConfirmed, isTrue);
    expect(l.asda.single.id, 'a1');
    expect(l.costco.single.stale, isTrue);
    expect(l.costcoUnavailable, isTrue);
    expect(l.updatedAt.isAtSameMomentAs(_t), isTrue);
  });

  test(
    'saving one key leaves other keys intact; re-saving replaces its own',
    () async {
      await svc.saveLink('h', _link('milk'));
      await svc.saveLink('h', _link('eggs', asdaId: 'e1'));
      await svc.saveLink('h', _link('milk', asdaId: 'a2'));
      final links = await svc.linksStream('h').first;
      expect(links.keys.toSet(), {'milk', 'eggs'});
      expect(links['milk']!.asda.single.id, 'a2');
      expect(links['eggs']!.asda.single.id, 'e1');
    },
  );

  test('item names with dots and slashes are safe keys', () async {
    await svc.saveLink('h', _link('2.5l milk / semi'));
    await svc.saveLink('h', _link('other'));
    final links = await svc.linksStream('h').first;
    expect(links.keys.toSet(), {'2.5l milk / semi', 'other'});
  });

  test('empty key is rejected', () async {
    expect(() => svc.saveLink('h', _link('')), throwsArgumentError);
  });

  test('removeLink deletes only that key; missing doc is a no-op', () async {
    await svc.removeLink('h', 'nothing');
    await svc.saveLink('h', _link('milk'));
    await svc.saveLink('h', _link('eggs'));
    await svc.removeLink('h', 'milk');
    expect((await svc.linksStream('h').first).keys, ['eggs']);
    await svc.removeLink('h', 'not-there');
    expect((await svc.linksStream('h').first).keys, ['eggs']);
  });

  test('a malformed entry is skipped, not fatal', () async {
    await svc.saveLink('h', _link('milk'));
    await db.doc('households/h/config/priceLinks').set({
      'links': {'bad': 'oops'},
    }, SetOptions(merge: true));
    expect((await svc.linksStream('h').first).keys, ['milk']);
  });

  test('settings default when the doc is missing, then round-trip', () async {
    final d = await svc.settingsStream('h').first;
    expect(d.asdaDelivery, 6.0);
    expect(d.costcoDelivery, 5.99);

    await svc.saveSettings(
      'h',
      const PriceFees(asdaDelivery: 4.5, costcoDelivery: 7),
    );
    final s = await svc.settingsStream('h').first;
    expect(s.asdaDelivery, 4.5);
    expect(s.costcoDelivery, 7.0);
  });

  test('never writes outside priceLinks / priceSettings', () async {
    await db.doc('households/h/config/apiKeys').set({'gemini': 'secret'});
    await db.doc('households/h/config/restockReminder').set({'enabled': true});
    await svc.saveLink('h', _link('milk'));
    await svc.removeLink('h', 'milk');
    await svc.saveSettings('h', const PriceFees());

    final ids = (await db.collection('households/h/config').get()).docs
        .map((d) => d.id)
        .toSet();
    expect(ids, {'apiKeys', 'restockReminder', 'priceLinks', 'priceSettings'});
    expect((await db.doc('households/h/config/apiKeys').get()).data(), {
      'gemini': 'secret',
    });
    expect((await db.doc('households/h/config/restockReminder').get()).data(), {
      'enabled': true,
    });
    // Other collections untouched.
    expect((await db.collection('households').get()).docs, isEmpty);
  });
}
