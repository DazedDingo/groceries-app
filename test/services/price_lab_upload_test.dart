import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/price_lab_upload.dart';

/// Dump with incompressible content so the gzip size scales with [kb].
Map<String, dynamic> _dump({int kb = 4, int pages = 3}) {
  final rnd = Random(42);
  String noise(int n) =>
      base64Encode(List<int>.generate(n, (_) => rnd.nextInt(256)));
  return {
    'appVersion': '1.2.3+4',
    'pages': [
      for (var i = 0; i < pages; i++)
        {'url': 'https://example.com/$i', 'html': noise(kb * 1024 ~/ pages)},
    ],
  };
}

List<int> _gz(Map<String, dynamic> m) =>
    GZipCodec(level: 9).encode(utf8.encode(jsonEncode(m)));

void main() {
  const hid = 'h1';

  group('chunkPriceLabDump', () {
    test('round-trips: join, base64 decode, gunzip, jsonDecode', () {
      final dump = _dump(kb: 20);
      final chunks = chunkPriceLabDump(_gz(dump), chunkChars: 1000);
      expect(chunks.length, greaterThan(1));
      final back = utf8.decode(
          gzip.decode(base64Decode(chunks.join())));
      expect(jsonDecode(back), dump);
    });

    test('every chunk respects the size bound', () {
      final chunks = chunkPriceLabDump(_gz(_dump(kb: 20)), chunkChars: 777);
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(777));
      }
      // All but the last are full.
      for (final c in chunks.take(chunks.length - 1)) {
        expect(c.length, 777);
      }
    });

    test('small payload is a single chunk', () {
      expect(chunkPriceLabDump([1, 2, 3]).length, 1);
    });
  });

  group('PriceLabUploader', () {
    test('writes chunk docs + manifest with correct counts', () async {
      final db = FakeFirebaseFirestore();
      final dump = _dump(kb: 20, pages: 3);
      final res = await PriceLabUploader(db, chunkChars: 4000)
          .upload(householdId: hid, dump: dump, appVersion: '1.2.3+4');

      final config = db.collection('households').doc(hid).collection('config');
      final all = await config.get();
      expect(all.docs.length, res.chunks + 1);

      final manifest = (await config.doc('priceLabDump').get()).data()!;
      expect(manifest['chunks'], res.chunks);
      expect(manifest['gzBytes'], res.gzBytes);
      expect(manifest['jsonBytes'], res.jsonBytes);
      expect(manifest['jsonBytes'], utf8.encode(jsonEncode(dump)).length);
      expect(manifest['pages'], 3);
      expect(manifest['appVersion'], '1.2.3+4');
      expect(manifest['encoding'], 'json+gzip+base64');
      expect(manifest['createdAt'], isA<Timestamp>());

      final parts = <String>[];
      for (var i = 0; i < res.chunks; i++) {
        final d = (await config.doc('priceLabDump_$i').get()).data()!;
        expect(d['index'], i);
        parts.add(d['data'] as String);
      }
      final gz = base64Decode(parts.join());
      expect(gz.length, res.gzBytes);
      expect(manifest['sha256'], sha256.convert(gz).toString());
      expect(jsonDecode(utf8.decode(gzip.decode(gz))), dump);
    });

    test('manifest is written after every chunk', () async {
      final db = FakeFirebaseFirestore();
      final config = db.collection('households').doc(hid).collection('config');
      final order = <String>[];
      final sub = config.snapshots().listen((s) {
        for (final c in s.docChanges) {
          if (c.type == DocumentChangeType.added) order.add(c.doc.id);
        }
      });
      final res = await PriceLabUploader(db, chunkChars: 4000).upload(
          householdId: hid, dump: _dump(kb: 20), appVersion: 'v');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(res.chunks, greaterThan(1));
      expect(order.last, 'priceLabDump');
      expect(order.where((id) => id == 'priceLabDump').length, 1);
      expect(order.length, res.chunks + 1);
    });

    test('more than 25 chunks throws and writes nothing', () async {
      final db = FakeFirebaseFirestore();
      final uploader = PriceLabUploader(db, chunkChars: 200);
      await expectLater(
        uploader.upload(
            householdId: hid, dump: _dump(kb: 20), appVersion: 'v'),
        throwsA(isA<PriceLabUploadException>()
            .having((e) => e.toString(), 'message', contains('KB'))),
      );
      final all = await db
          .collection('households')
          .doc(hid)
          .collection('config')
          .get();
      expect(all.docs, isEmpty);
    });

    test('never touches doc ids outside the priceLabDump prefix', () async {
      final db = FakeFirebaseFirestore();
      final config = db.collection('households').doc(hid).collection('config');
      await config.doc('apiKeys').set({'k': 'secret'});
      await config.doc('restockReminder').set({'enabled': true});

      await PriceLabUploader(db, chunkChars: 4000)
          .upload(householdId: hid, dump: _dump(kb: 20), appVersion: 'v');

      expect((await config.doc('apiKeys').get()).data(), {'k': 'secret'});
      expect((await config.doc('restockReminder').get()).data(),
          {'enabled': true});
      final ids = (await config.get()).docs.map((d) => d.id);
      for (final id in ids) {
        if (id == 'apiKeys' || id == 'restockReminder') continue;
        expect(id, startsWith('priceLabDump'));
      }
      // Nothing written at the household doc or other collections.
      final hh = await db.collection('households').doc(hid).get();
      expect(hh.exists, isFalse);
    });
  });
}
