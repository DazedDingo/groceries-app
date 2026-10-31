import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Doc-ID prefix for every document the Price lab upload touches inside
/// `households/{hid}/config`. That folder also holds unrelated docs (apiKeys,
/// webhookStatus, ...), so nothing outside this prefix may ever be written.
const String priceLabDumpDocPrefix = 'priceLabDump';

/// Max chunk docs per upload (~22 MB of base64 at the default chunk size).
const int priceLabMaxChunks = 25;

/// Default max characters per chunk doc (Firestore docs cap at 1 MiB).
const int priceLabChunkChars = 900000;

/// base64-encodes [gzBytes] and splits the result into strings of at most
/// [chunkChars] characters.
List<String> chunkPriceLabDump(
  List<int> gzBytes, {
  int chunkChars = priceLabChunkChars,
}) {
  assert(chunkChars > 0);
  final b64 = base64Encode(gzBytes);
  final out = <String>[];
  for (var i = 0; i < b64.length; i += chunkChars) {
    final end = i + chunkChars < b64.length ? i + chunkChars : b64.length;
    out.add(b64.substring(i, end));
  }
  return out;
}

class PriceLabUploadResult {
  const PriceLabUploadResult({
    required this.chunks,
    required this.gzBytes,
    required this.jsonBytes,
  });

  final int chunks;
  final int gzBytes;
  final int jsonBytes;
}

class PriceLabUploadException implements Exception {
  PriceLabUploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Uploads a Price lab dump into Firestore as gzipped+base64 chunk docs plus
/// a manifest doc, all under `households/{hid}/config/priceLabDump*`.
class PriceLabUploader {
  PriceLabUploader(this._db, {this.chunkChars = priceLabChunkChars});

  final FirebaseFirestore _db;
  final int chunkChars;

  Future<PriceLabUploadResult> upload({
    required String householdId,
    required Map<String, dynamic> dump,
    required String appVersion,
  }) async {
    final jsonBytes = utf8.encode(jsonEncode(dump));
    final gz = GZipCodec(level: 9).encode(jsonBytes);
    final chunks = chunkPriceLabDump(gz, chunkChars: chunkChars);
    if (chunks.length > priceLabMaxChunks) {
      throw PriceLabUploadException(
          'Dump too large to upload: ${(gz.length / 1024).round()} KB '
          'compressed needs ${chunks.length} chunks '
          '(max $priceLabMaxChunks).');
    }

    final config =
        _db.collection('households').doc(householdId).collection('config');

    // One set() per chunk: a single batch could exceed the 10 MiB request cap.
    for (var i = 0; i < chunks.length; i++) {
      await config
          .doc('${priceLabDumpDocPrefix}_$i')
          .set({'data': chunks[i], 'index': i});
    }

    final pages = dump['pages'];
    // Manifest last so a reader never sees a partial upload.
    await config.doc(priceLabDumpDocPrefix).set({
      'createdAt': FieldValue.serverTimestamp(),
      'chunks': chunks.length,
      'gzBytes': gz.length,
      'jsonBytes': jsonBytes.length,
      'sha256': sha256.convert(gz).toString(),
      'appVersion': appVersion,
      'pages': pages is List ? pages.length : 0,
      'encoding': 'json+gzip+base64',
    });

    return PriceLabUploadResult(
      chunks: chunks.length,
      gzBytes: gz.length,
      jsonBytes: jsonBytes.length,
    );
  }
}
