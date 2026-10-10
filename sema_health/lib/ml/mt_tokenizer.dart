import 'dart:convert';
import 'dart:io';

/// Pure-Dart implementation of the NLLB-200 SentencePiece-BPE tokenizer
/// shipped as a HuggingFace `tokenizer.json` (Fast Tokenizers format).
///
/// What this covers and what it doesn't:
/// - **Pre-tokenizer**: Metaspace (`▁`-prepend, space-replacement) — full.
/// - **Model**: ranked BPE merges with `fuse_unk` — full.
/// - **Post-processor**: NLLB template `[<src_lang>, ...ids, </s>]` — full.
/// - **Decoder**: Metaspace inverse (`▁` → space, strip leading) — full.
/// - **Normalizer (Precompiled NMT-NFKC charsmap)**: skipped. SentencePiece's
///   precompiled normalizer is not implementable without the binary trie
///   it ships with. For our African-language → English use case the input
///   is overwhelmingly ASCII / Latin-1 plus a handful of accented codepoints
///   that the BPE handles directly. We do basic whitespace cleanup (NFC
///   isn't available in dart:core either). Quality cost is small and
///   measurable; we can revisit if it bites.
///
/// Built once at translator load and held for the life of the session —
/// parsing the 32 MB `tokenizer.json` takes a couple seconds on a
/// mid-tier phone, but vocab + merges then sit in RAM as plain Dart
/// maps (~30 MB resident, well below Gemma's footprint).
class NllbTokenizer {
  NllbTokenizer._({
    required Map<String, int> vocab,
    required Map<int, String> idToToken,
    required Map<String, int> mergeRanks,
    required this.bosId,
    required this.eosId,
    required this.padId,
    required this.unkId,
    required this.fuseUnk,
  })  : _vocab = vocab,
        _idToToken = idToToken,
        _mergeRanks = mergeRanks;

  final Map<String, int> _vocab;
  final Map<int, String> _idToToken;

  /// "first second" → rank. Lower rank = higher priority (merged first).
  final Map<String, int> _mergeRanks;

  final int bosId;
  final int eosId;
  final int padId;
  final int unkId;
  final bool fuseUnk;

  static const String _spaceMarker = '▁'; // ▁

  /// Construct from the on-device tokenizer.json file.
  static Future<NllbTokenizer> fromFile(File f) async {
    final raw = await f.readAsString();
    return fromJsonString(raw);
  }

  /// Construct from a tokenizer.json payload already in memory.
  static NllbTokenizer fromJsonString(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;

    final modelNode = root['model'] as Map<String, dynamic>;
    if (modelNode['type'] != 'BPE') {
      throw StateError(
        'Expected BPE tokenizer model, got "${modelNode['type']}". '
        'NLLB exports use BPE; this looks like a different model.',
      );
    }

    final rawVocab = modelNode['vocab'] as Map<String, dynamic>;
    final vocab = <String, int>{};
    final idToToken = <int, String>{};
    rawVocab.forEach((tok, id) {
      final i = (id as num).toInt();
      vocab[tok] = i;
      idToToken[i] = tok;
    });

    // `added_tokens` (special tokens incl. all 200 NLLB language codes) are
    // separate from the vocab block in tokenizer.json but already present
    // in the BPE vocab too. Keep both indices in sync just in case.
    final added = root['added_tokens'] as List<dynamic>? ?? const [];
    for (final entry in added) {
      final m = entry as Map<String, dynamic>;
      final content = m['content'] as String;
      final id = (m['id'] as num).toInt();
      vocab[content] = id;
      idToToken[id] = content;
    }

    final mergesRaw = modelNode['merges'] as List<dynamic>;
    final merges = <String, int>{};
    for (var i = 0; i < mergesRaw.length; i++) {
      final m = mergesRaw[i];
      String key;
      if (m is List) {
        key = '${m[0]} ${m[1]}';
      } else if (m is String) {
        key = m;
      } else {
        continue;
      }
      merges[key] = i;
    }

    final unkTok = modelNode['unk_token'] as String? ?? '<unk>';
    final fuseUnk = (modelNode['fuse_unk'] as bool?) ?? true;

    return NllbTokenizer._(
      vocab: vocab,
      idToToken: idToToken,
      mergeRanks: merges,
      bosId: vocab['<s>'] ?? 0,
      eosId: vocab['</s>'] ?? 2,
      padId: vocab['<pad>'] ?? 1,
      unkId: vocab[unkTok] ?? 3,
      fuseUnk: fuseUnk,
    );
  }

  /// Look up the NLLB language token id (e.g. `eng_Latn` → 256047).
  /// Returns null if [langCode] isn't in the model's special tokens.
  int? langTokenId(String langCode) => _vocab[langCode];

  /// True iff every needed special token is present. Useful as a smoke
  /// test right after construction.
  bool supportsLanguages(Iterable<String> langCodes) =>
      langCodes.every((c) => _vocab.containsKey(c));

  /// Encode [text] for an NLLB translation pass.
  ///
  /// Wrapping follows NLLB's TemplateProcessing:
  ///   `[<src_lang_id>, ...bpe_ids, </s>]`
  ///
  /// Throws [ArgumentError] if [srcLang] isn't a known language token.
  List<int> encode(String text, {required String srcLang}) {
    final srcId = _vocab[srcLang];
    if (srcId == null) {
      throw ArgumentError.value(srcLang, 'srcLang',
          'Not a known NLLB language token (e.g. swh_Latn, aka_Latn).');
    }

    final cleaned = _basicWhitespace(text);
    final chunks = _metaspacePreTokenize(cleaned);

    final out = <int>[srcId];
    int? lastEmittedUnk;
    for (final chunk in chunks) {
      final pieces = _bpe(chunk);
      for (final piece in pieces) {
        final id = _vocab[piece] ?? unkId;
        if (fuseUnk && id == unkId && lastEmittedUnk == unkId) {
          continue; // collapse consecutive UNKs
        }
        out.add(id);
        lastEmittedUnk = id;
      }
    }
    out.add(eosId);
    return out;
  }

  /// Decode token ids back to text. Skips special tokens (BOS/EOS/PAD/UNK
  /// + language tokens) and undoes the Metaspace prefix.
  ///
  /// We treat anything in the special-token id range (0..3 plus the
  /// 256000..256205 NLLB language block) as non-printable.
  String decode(List<int> ids, {bool skipSpecial = true}) {
    final buf = StringBuffer();
    for (final id in ids) {
      if (skipSpecial && _isSpecial(id)) continue;
      final tok = _idToToken[id];
      if (tok == null) continue;
      buf.write(tok);
    }
    final raw = buf.toString();
    // Metaspace inverse: ▁ → space, then strip the leading space NLLB
    // always emits (`prepend_scheme: always`).
    final spaced = raw.replaceAll(_spaceMarker, ' ');
    return spaced.startsWith(' ') ? spaced.substring(1) : spaced;
  }

  bool _isSpecial(int id) {
    if (id == bosId || id == eosId || id == padId || id == unkId) return true;
    // NLLB language tokens occupy a contiguous tail block.
    if (id >= 256001 && id <= 256205) return true;
    return false;
  }

  /// Whitespace cleanup standing in for the Precompiled NMT-NFKC step.
  /// Collapses runs of whitespace and trims; doesn't touch unicode forms.
  static String _basicWhitespace(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Metaspace pre-tokenizer (`replacement: ▁`, `prepend_scheme: always`,
  /// `split: true`):
  ///   "hello world" → ["▁hello", "▁world"]
  ///   ""            → []
  static List<String> _metaspacePreTokenize(String text) {
    if (text.isEmpty) return const [];
    final replaced = '$_spaceMarker${text.replaceAll(' ', _spaceMarker)}';
    // Split on the marker but keep it as the leading char of each chunk.
    final out = <String>[];
    var start = 0;
    for (var i = 1; i < replaced.length; i++) {
      if (replaced[i] == _spaceMarker) {
        out.add(replaced.substring(start, i));
        start = i;
      }
    }
    if (start < replaced.length) out.add(replaced.substring(start));
    return out;
  }

  /// Apply ranked BPE merges to one pre-tokenized chunk.
  ///
  /// Operates on Unicode codepoints (not UTF-16 code units) so e.g.
  /// `Ẹ` (U+1EB8) stays one symbol instead of splitting into a surrogate
  /// pair the merges can't see.
  List<String> _bpe(String chunk) {
    if (chunk.isEmpty) return const [];
    var word = chunk.runes.map(String.fromCharCode).toList(growable: true);
    if (word.length == 1) return word;

    while (true) {
      // Find the lowest-rank mergeable pair.
      int bestRank = -1;
      int bestIdx = -1;
      for (var i = 0; i < word.length - 1; i++) {
        final pairKey = '${word[i]} ${word[i + 1]}';
        final rank = _mergeRanks[pairKey];
        if (rank == null) continue;
        if (bestRank == -1 || rank < bestRank) {
          bestRank = rank;
          bestIdx = i;
        }
      }
      if (bestIdx == -1) break;

      // Merge every non-overlapping occurrence of that pair in one pass.
      final first = word[bestIdx];
      final second = word[bestIdx + 1];
      final merged = first + second;
      final next = <String>[];
      var i = 0;
      while (i < word.length) {
        if (i < word.length - 1 && word[i] == first && word[i + 1] == second) {
          next.add(merged);
          i += 2;
        } else {
          next.add(word[i]);
          i += 1;
        }
      }
      word = next;
      if (word.length == 1) break;
    }
    return word;
  }
}
