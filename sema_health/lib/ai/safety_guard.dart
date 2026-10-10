import '../data/seed/first_aid_models.dart';
import 'sema_reply.dart';

/// Last-line filter on every text destined for the user.
///
/// Two stages, mirroring `ARCHITECTURE/04-ml-and-ai.md` "Safety guard":
///
/// 1. **Regex blocklist.** Catches patterns we never want surfaced
///    regardless of source — explicit dosages, "I diagnose you with",
///    suicide-method names, etc. Bundled, periodically reviewed.
/// 2. **Drug whitelist.** When a reply mentions a drug name, the name
///    must appear in the matched first-aid entry's `medications:`
///    array. The KG is the single source of truth for what drugs are
///    safe to suggest.
///
/// The in-house ONNX safety classifier described in the architecture
/// is a v2 layer; this Dart guard is the v1 floor.
class SafetyGuard {
  SafetyGuard({this.repairReply});

  /// Optional override used by tests. Production callers should rely
  /// on the default repair reply that ships with the guard.
  final SemaReply Function(SemaReply original, GuardViolation reason)?
      repairReply;

  /// Run the guard. Returns either an approved [SemaReply] or a
  /// safe-template repair. Either way, the result is what the chat
  /// bubble should render.
  GuardResult check(SemaReply reply, {FirstAidEntry? matchedEntry}) {
    final blocklistHit = _scanBlocklist(reply);
    if (blocklistHit != null) {
      return GuardResult.repaired(
        original: reply,
        repaired: _defaultRepair(reply, blocklistHit),
        reason: blocklistHit,
      );
    }

    final drugHit = _scanDrugs(reply, matchedEntry);
    if (drugHit != null) {
      return GuardResult.repaired(
        original: reply,
        repaired: _defaultRepair(reply, drugHit),
        reason: drugHit,
      );
    }

    return GuardResult.passed(reply);
  }

  /// Public helper: is this drug allowed in a reply tied to [entry]?
  /// Used by the eventual Gemma verbalizer before rewriting `body`,
  /// so the LLM can be told what drugs it may mention.
  bool isAllowedDrug({required String drugName, FirstAidEntry? entry}) {
    if (entry == null) return false;
    return entry.allowsMedication(drugName);
  }

  // ─── Stage 1 · regex blocklist ─────────────────────────────────

  static final List<_BlocklistPattern> _blocklist = [
    // Dosage strings — "200 mg", "1.5 mL twice daily", etc. Even when
    // a drug is whitelisted by an entry, we never have Gemma name a
    // specific dose; that crosses into prescribing.
    _BlocklistPattern(
      RegExp(r'\b\d+(\.\d+)?\s*(?:mg|mcg|μg|ug|mL|ml|grams?|g|IU)\b',
          caseSensitive: false),
      GuardViolation.dosagePhrase,
    ),
    // "Take N pills", "N tablets" — same family of prescribing speech.
    _BlocklistPattern(
      RegExp(r'\btake\s+\d+\s+(?:pills?|tablets?|capsules?)\b',
          caseSensitive: false),
      GuardViolation.dosagePhrase,
    ),
    // Hard-claim diagnoses. "You have X" / "Your child has X" /
    // "I diagnose ...". The architecture system prompt forbids these
    // already; the guard is the regex floor.
    _BlocklistPattern(
      RegExp(
          r'\b(?:I\s+diagnose|you\s+(?:have|are\s+having)\s+(?:a|an)?\s*'
          r'(?:heart\s+attack|stroke|cancer|sepsis|meningitis|covid|tuberculosis|malaria))\b',
          caseSensitive: false),
      GuardViolation.diagnosticClaim,
    ),
    // "Definitely / 100% / for sure" + medical noun. Hedge enforcement.
    _BlocklistPattern(
      RegExp(
          r'\b(?:definitely|certainly|100\s*%|for\s+sure)\s+(?:diabetes|cancer|heart\s+attack|infection|stroke)\b',
          caseSensitive: false),
      GuardViolation.diagnosticClaim,
    ),
  ];

  GuardViolation? _scanBlocklist(SemaReply reply) {
    final corpus = StringBuffer()
      ..writeln(reply.headline)
      ..writeln(reply.body);
    for (final s in reply.steps) {
      corpus.writeln(s.text);
    }
    for (final d in reply.donts) {
      corpus.writeln(d);
    }
    final text = corpus.toString();
    for (final p in _blocklist) {
      if (p.pattern.hasMatch(text)) return p.violation;
    }
    return null;
  }

  // ─── Stage 2 · drug whitelist ──────────────────────────────────
  //
  // We scan reply text for a small set of known drug nouns. If any
  // appear and they are NOT in the matched entry's `medications:`
  // array, we repair. The known drug list is intentionally short and
  // English-only — this guard runs against the English-side reply
  // before any MT-out, which matches the architecture's "SafetyGuard
  // sits on Gemma's English output, before any translation-out".

  static const List<String> _knownDrugTerms = [
    'aspirin',
    'ibuprofen',
    'acetaminophen',
    'paracetamol',
    'epinephrine',
    'epipen',
    'benadryl',
    'diphenhydramine',
    'hydrocortisone',
    'calamine',
    'antibiotic ointment',
    'petroleum jelly',
  ];

  GuardViolation? _scanDrugs(SemaReply reply, FirstAidEntry? entry) {
    final corpus =
        '${reply.headline}\n${reply.body}\n${reply.steps.map((s) => s.text).join('\n')}\n${reply.donts.join('\n')}'
            .toLowerCase();
    for (final drug in _knownDrugTerms) {
      if (!corpus.contains(drug)) continue;
      // Drug mentioned. Check if the matched entry whitelists it.
      if (entry == null) return GuardViolation.unwhitelistedDrug;
      if (!entry.allowsMedication(drug) &&
          !_aliasMatches(drug, entry)) {
        return GuardViolation.unwhitelistedDrug;
      }
    }
    return null;
  }

  /// EpiPen ↔ Epinephrine, paracetamol ↔ acetaminophen aliasing.
  bool _aliasMatches(String drug, FirstAidEntry entry) {
    const aliases = <String, List<String>>{
      'epipen': ['epinephrine'],
      'epinephrine': ['epipen', 'adrenaline'],
      'paracetamol': ['acetaminophen'],
      'acetaminophen': ['paracetamol'],
      'diphenhydramine': ['benadryl'],
      'benadryl': ['diphenhydramine'],
    };
    final candidates = aliases[drug] ?? const <String>[];
    for (final c in candidates) {
      if (entry.allowsMedication(c)) return true;
    }
    return false;
  }

  // ─── Repair ────────────────────────────────────────────────────

  SemaReply _defaultRepair(SemaReply original, GuardViolation reason) {
    if (repairReply != null) return repairReply!(original, reason);
    return SemaReply(
      tone: original.tone,
      headline: 'Let me connect you with a clinician',
      body: "I'm not the right place to answer that part of your "
          "question. The safest next step is to speak with a clinician "
          "or call emergency services if this is urgent.",
      cta: original.cta,
      audit: original.audit,
    );
  }
}

class _BlocklistPattern {
  const _BlocklistPattern(this.pattern, this.violation);
  final RegExp pattern;
  final GuardViolation violation;
}

enum GuardViolation {
  dosagePhrase,
  diagnosticClaim,
  unwhitelistedDrug,
}

class GuardResult {
  const GuardResult._({
    required this.passed,
    required this.reply,
    this.original,
    this.violation,
  });

  factory GuardResult.passed(SemaReply r) =>
      GuardResult._(passed: true, reply: r);

  factory GuardResult.repaired({
    required SemaReply original,
    required SemaReply repaired,
    required GuardViolation reason,
  }) =>
      GuardResult._(
        passed: false,
        reply: repaired,
        original: original,
        violation: reason,
      );

  /// True when the original reply passed the guard unchanged.
  final bool passed;

  /// Reply to render to the user — original if [passed], else the
  /// repaired safe template.
  final SemaReply reply;

  /// What the guard saw before repairing. Logged for auditor view.
  final SemaReply? original;
  final GuardViolation? violation;
}
