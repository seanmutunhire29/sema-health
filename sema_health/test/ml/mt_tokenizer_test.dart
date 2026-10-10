// Smoke tests for the NLLB BPE tokenizer. They run against the actual
// bundled `models/mt/tokenizer.json`, so a regression in metaspace
// handling, merge ranking, or special-token lookup fails here loudly
// rather than silently producing garbage translations on device.
//
// Skipped when the tokenizer file isn't present (e.g. CI without the
// 30 MB weights pulled in) — the absence message tells you what's
// missing rather than failing red.

import 'dart:io';

import 'package:test/test.dart';
import 'package:sema_health/ml/mt_tokenizer.dart';

void main() {
  final f = File('models/mt/tokenizer.json');
  if (!f.existsSync()) {
    test('tokenizer.json present',
        () => fail('models/mt/tokenizer.json missing — pull NLLB bundle.'),
        skip: 'NLLB tokenizer.json not on disk; skipping MT tests.');
    return;
  }

  late NllbTokenizer tok;
  setUpAll(() async {
    tok = await NllbTokenizer.fromFile(f);
  });

  group('NllbTokenizer', () {
    test('reports the right ids for the sentinel special tokens', () {
      expect(tok.bosId, 0);
      expect(tok.padId, 1);
      expect(tok.eosId, 2);
      expect(tok.unkId, 3);
    });

    test('resolves NLLB language codes to their vocabulary slot', () {
      // Verified against the model's special_tokens_map.json.
      expect(tok.langTokenId('eng_Latn'), 256047);
      expect(tok.langTokenId('swh_Latn'), isNotNull);
      expect(tok.langTokenId('aka_Latn'), isNotNull);
      expect(tok.langTokenId('yor_Latn'), isNotNull);
      expect(tok.langTokenId('not_a_real_lang'), isNull);
    });

    test('encode wraps the sequence as [src_lang, ...subwords, eos]', () {
      final ids = tok.encode('hello', srcLang: 'eng_Latn');
      expect(ids.first, 256047, reason: 'First token must be src lang id.');
      expect(ids.last, tok.eosId, reason: 'Last token must be </s>.');
      expect(ids.length, greaterThan(2));
    });

    test('encode/decode round-trip preserves common ASCII content', () {
      // "I have a fever and headache" — short clinical sentence.
      const en = 'I have a fever and headache';
      final ids = tok.encode(en, srcLang: 'eng_Latn');
      // Drop the language prefix + eos before decoding back.
      final body = ids.sublist(1, ids.length - 1);
      final decoded = tok.decode(body);
      // BPE splits on metaspace, so re-joining gives back the original
      // text exactly (metaspace replacement is the only normalization
      // we apply).
      expect(decoded, en);
    });

    test('decode strips special tokens by default', () {
      final ids = tok.encode('test', srcLang: 'eng_Latn');
      final decoded = tok.decode(ids);
      expect(decoded.contains('eng_Latn'), isFalse);
      expect(decoded.contains('</s>'), isFalse);
      expect(decoded, 'test');
    });

    test('throws ArgumentError on an unknown source language', () {
      expect(
        () => tok.encode('hello', srcLang: 'klingon_Klin'),
        throwsArgumentError,
      );
    });

    test('handles empty / whitespace-only input as a 2-token wrapper',
        () {
      // Per the basic-whitespace cleanup, "" and "   " both collapse
      // to nothing and we emit just [src_lang, eos].
      final empty = tok.encode('', srcLang: 'eng_Latn');
      expect(empty, [256047, tok.eosId]);
      final ws = tok.encode('   ', srcLang: 'eng_Latn');
      expect(ws, [256047, tok.eosId]);
    });
  });
}
