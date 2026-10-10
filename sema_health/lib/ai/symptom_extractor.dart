import '../data/seed/first_aid_models.dart';

/// Extracts symptom slugs and a few well-known vitals from a user's
/// turn. Pure Dart, deterministic, closed-vocabulary.
///
/// The architecture's long-term plan is to replace this with the
/// in-house ONNX NLU model (see `ARCHITECTURE/04-ml-and-ai.md` "NLU").
/// Until then this class fills the seam — same input/output contract —
/// so the triage engine and chat agent never need to know the
/// difference. When the NLU model lands the agent calls a different
/// extractor; nothing else changes.
///
/// Quality targets (v1, this implementation):
/// - **Recall over precision.** Better to over-extract and let the
///   triage rules sort it out than to miss a red-flag symptom.
/// - **Closed vocabulary only.** Output slugs MUST be ids in
///   `symptoms.yaml`; anything else is dropped. This is what makes the
///   downstream rules engine deterministic.
/// - **No medical inference.** The extractor never converts "I'm
///   pregnant and bleeding" → `vaginal-bleeding-pregnancy`. It extracts
///   `heavy-bleeding` (or whatever phrase fired); the rule engine,
///   reading the bio profile, makes the pregnancy combination call.
class SymptomExtractor {
  SymptomExtractor._({
    required List<_PhraseHit> phrases,
  }) : _phrases = phrases;

  /// Phrases sorted longest-first. Multi-word matches must win over
  /// single-word ones (e.g. "swelling tongue" beats "swelling").
  final List<_PhraseHit> _phrases;

  /// Build an extractor from the symptom catalog. Each symptom's `id`
  /// (with hyphens turned into spaces) and every alias becomes a phrase
  /// pointing back at the slug.
  factory SymptomExtractor.fromSymptoms(Iterable<Symptom> symptoms) {
    final phrases = <_PhraseHit>[];
    for (final s in symptoms) {
      // The slug itself, hyphens → spaces. Catches users who type the
      // exact term ("nosebleed", "heat stroke", etc.).
      phrases.add(_PhraseHit(_normalize(s.id.replaceAll('-', ' ')), s.id));
      for (final a in s.aliases) {
        phrases.add(_PhraseHit(_normalize(a), s.id));
      }
    }
    // Longest first so multi-word matches aren't shadowed by their
    // single-word substrings during the pass below.
    phrases.sort((a, b) => b.phrase.length.compareTo(a.phrase.length));
    return SymptomExtractor._(phrases: phrases);
  }

  /// Run extraction. Returns the symptom slugs found and any vitals
  /// the extractor could pick out of the raw text.
  ExtractionResult extract(String userText) {
    final text = _normalize(userText);
    final tokens = _tokenize(text);
    final slugs = <String>{};
    for (final p in _phrases) {
      if (_containsAsToken(text, p.phrase)) {
        slugs.add(p.slug);
        continue;
      }
      // Word-order-tolerant fallback for multi-word phrases. Users say
      // "severe allergic reaction" rather than the slug-shaped
      // "allergic reaction severe"; the contiguous match misses, this
      // bag-of-words match catches. Single-token phrases are excluded
      // because they'd already match contiguously above; allowing them
      // here would just duplicate work.
      if (_phraseHasMultipleTokens(p.phrase) &&
          _bagOfWordsMatch(tokens, p.phrase)) {
        slugs.add(p.slug);
      }
    }
    final vitals = _extractVitals(userText);
    return ExtractionResult(slugs: slugs, vitals: vitals);
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  /// Lowercase, collapse whitespace, strip punctuation that breaks
  /// substring matches without changing meaning. Apostrophes survive
  /// ("can't"); hyphens become spaces so "twi-fold" doesn't appear
  /// in the middle of a slug.
  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\.,!?:;\(\)\[\]"]+'), ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Split normalised text into word tokens for bag-of-words matching.
  static List<String> _tokenize(String normalised) =>
      normalised.split(' ').where((t) => t.isNotEmpty).toList(growable: false);

  static bool _phraseHasMultipleTokens(String phrase) =>
      phrase.contains(' ');

  /// Bag-of-words match. Every token in [phrase] must appear as a
  /// distinct token in [haystackTokens]. Tokens shorter than 4 chars are
  /// ignored (matches "of", "an", "to" cause false positives in symptom
  /// aliases). Returns false if every phrase token is below the length
  /// floor — that would signal nothing.
  static bool _bagOfWordsMatch(
    List<String> haystackTokens,
    String phrase,
  ) {
    final phraseTokens = phrase
        .split(' ')
        .where((t) => t.length >= 4)
        .toSet();
    if (phraseTokens.isEmpty) return false;
    for (final t in phraseTokens) {
      if (!haystackTokens.contains(t)) return false;
    }
    return true;
  }

  /// Substring match with word-boundary semantics. We can't use a real
  /// regex word-boundary safely on aliases that contain spaces, so we
  /// look for the phrase surrounded by either string boundaries or
  /// non-word characters.
  static bool _containsAsToken(String haystack, String needle) {
    if (needle.isEmpty) return false;
    final idx = haystack.indexOf(needle);
    if (idx < 0) return false;
    final before = idx == 0 ? ' ' : haystack[idx - 1];
    final afterIdx = idx + needle.length;
    final after = afterIdx >= haystack.length ? ' ' : haystack[afterIdx];
    final wordChar = RegExp(r"[a-z0-9']");
    return !wordChar.hasMatch(before) && !wordChar.hasMatch(after);
  }

  /// v1 vital extraction: only `body_temp_c`. Reads patterns like:
  /// - "38.5 C" / "38.5°C" / "38.5°C" / "38.5 c"
  /// - "temperature 39"
  /// - "39 degrees" (interpreted as Celsius — the target region's
  ///   default; users with Fahrenheit say "F" explicitly).
  ///
  /// On Fahrenheit ("103 F", "103°F"), converts to Celsius.
  ///
  /// Returns at most one body_temp_c value; if multiple appear, the
  /// LAST one wins (treats follow-up clarifications as authoritative).
  static Map<String, num> _extractVitals(String raw) {
    final out = <String, num>{};
    final lc = raw.toLowerCase();

    // Celsius: number with optional decimal, optional space, °/˚, c
    final cRe = RegExp(
      r'(\d{2,3}(?:\.\d)?)\s*(?:°|˚|deg(?:rees)?)?\s*c\b',
    );
    // Fahrenheit: explicit F (so "39 c" doesn't match "39 f")
    final fRe = RegExp(
      r'(\d{2,3}(?:\.\d)?)\s*(?:°|˚|deg(?:rees)?)?\s*f\b',
    );
    // Bare "X degrees" — Celsius default for our region.
    final dRe = RegExp(r'(\d{2,3}(?:\.\d)?)\s*degrees?\b');
    // "temperature 38.5"
    final tempRe = RegExp(
      r'(?:temperature|temp|fever)\s*(?:of|is|at|=)?\s*(\d{2,3}(?:\.\d)?)',
    );

    final candidates = <(double, String)>[];
    for (final m in cRe.allMatches(lc)) {
      candidates.add((double.parse(m.group(1)!), 'c'));
    }
    for (final m in fRe.allMatches(lc)) {
      candidates.add((double.parse(m.group(1)!), 'f'));
    }
    for (final m in dRe.allMatches(lc)) {
      candidates.add((double.parse(m.group(1)!), 'c'));
    }
    for (final m in tempRe.allMatches(lc)) {
      candidates.add((double.parse(m.group(1)!), 'c'));
    }

    if (candidates.isEmpty) return out;

    // Take the last reading; if it looks Fahrenheit-shaped (>= 90 in
    // Celsius is impossible), force F→C even if it was tagged C/d.
    var (val, unit) = candidates.last;
    if (unit == 'c' && val >= 90) {
      unit = 'f';
    }
    final celsius = unit == 'f' ? (val - 32) * 5 / 9 : val;

    // Plausibility filter — body temps under 30 or over 45 are noise.
    if (celsius < 30 || celsius > 45) return out;
    out['body_temp_c'] = double.parse(celsius.toStringAsFixed(1));
    return out;
  }
}

class _PhraseHit {
  const _PhraseHit(this.phrase, this.slug);
  final String phrase;
  final String slug;
}

/// Result of one extraction pass.
class ExtractionResult {
  const ExtractionResult({required this.slugs, required this.vitals});
  final Set<String> slugs;
  final Map<String, num> vitals;

  bool get isEmpty => slugs.isEmpty && vitals.isEmpty;
}
