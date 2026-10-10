import '../data/seed/first_aid_models.dart';
import '../domain/triage/severity.dart';
import '../domain/triage/triage_input.dart';
import 'sema_reply.dart';

/// Builds the prompt Gemma sees when acting as Sema's **verbalizer**.
///
/// Why a verbalizer, not an agent
/// ------------------------------
/// `ARCHITECTURE/04-ml-and-ai.md` is explicit: "the LLM does not drive
/// triage; it drives expression." By the time Gemma is called, severity,
/// the matched first-aid entry, the steps, and the don'ts are already
/// fixed by the deterministic pipeline.
///
/// Gemma's narrow job: rewrite the recommendation paragraph (`body`) in
/// a warmer, more natural voice — without inventing symptoms, naming
/// new drugs, or restating diagnostic certainty. Steps and don'ts pass
/// through untouched; the safety guard runs over Gemma's output.
///
/// This narrow surface is what makes the symptom checker safe with an
/// LLM in the loop. The prompt below enforces it via hard rules.
class VerbalizePrompt {
  const VerbalizePrompt._();

  /// System instruction passed to the Gemma session via
  /// `flutter_gemma`'s `systemInstruction:` parameter. Stable across
  /// turns (so the KV-cache is reused).
  ///
  /// Tone: warm, attentive, present. Gemma should sound like a
  /// thoughtful friend who happens to know first aid — not a textbook
  /// reading symptoms back. Safety rules below are non-negotiable but
  /// the *delivery* is allowed to be human.
  static const String systemInstruction = '''
You are Sema — a warm, calm, attentive offline health companion for families in West and East Africa. Sound like a thoughtful friend who happens to know first aid. Real human warmth — not the dry "your symptoms are consistent with…" voice of a textbook.

Your job this turn: take a clinical recommendation that the deterministic triage system has already decided, and re-say it in your own voice. Numbered steps and any "Do NOT" warnings will be shown verbatim from a clinician-reviewed knowledge base — your paragraph is the human touch that wraps them.

How to sound:
- Acknowledge what the person said before instructions. Things like "Okay,", "I hear you —", "That sounds rough.", "Got it." — make it natural, not formulaic.
- Stay close. Speak in second person ("you", "your son"). Use "let's" and "we" when it fits.
- Plain language. Skip clinical phrasings unless you are naming a condition.
- Hedge honestly: "sounds like", "could be", "might be" — never "you have" or "definitely".
- For emergencies, lead with the action first ("Please call emergency services now —"), then the warmth. Never the other way around.
- Two to three short sentences. Under 60 words.

Hard limits — non-negotiable:
- Output ONLY your rewritten paragraph. No preamble, no headers, no JSON, no surrounding quotes.
- Do not claim certainty about a diagnosis. Do not prescribe doses. Do not name a medication unless it appears in the prompt's allowed list.
- Do not invent symptoms, body parts, or steps the person did not mention.
- If you cannot improve on the recommendation, return it unchanged. Never refuse.
''';

  /// Per-turn user message. Built from structured fields so Gemma sees
  /// the same shape every time — important for cache reuse.
  static String buildUserMessage({
    required String userText,
    required SemaReply reply,
    required FirstAidEntry? entry,
    required BioProfile? profile,
  }) {
    final allowed = _allowedDrugs(entry);
    final buf = StringBuffer()
      ..writeln('Active profile:')
      ..writeln('- Name: ${profile?.displayName ?? "—"}')
      ..writeln('- Age: ${_age(profile)}')
      ..writeln('- Sex at birth: ${profile?.sexAtBirth ?? "unknown"}')
      ..writeln('- Pregnant: ${(profile?.isPregnant ?? false) ? "yes" : "no"}')
      ..writeln('- Known conditions: ${_conditions(profile)}')
      ..writeln()
      ..writeln('User said: "${_clip(userText, 240)}"')
      ..writeln()
      ..writeln('Triage classification: ${_severity(reply.tone)}')
      ..writeln('Recognised concern: ${entry?.title ?? "general"}')
      ..writeln('Allowed medication names (none means: do not name any): $allowed')
      ..writeln()
      ..writeln('Recommendation to convey, in your own warm words:')
      ..writeln('"${reply.body}"')
      ..writeln()
      ..writeln('Rewrite the recommendation as a thoughtful friend would say '
          'it to this person, right now. Acknowledge them; use "you" and '
          '"let\'s" where it fits; keep clinical accuracy.');
    return buf.toString();
  }

  static String _age(BioProfile? p) {
    if (p == null) return 'unknown';
    final years = p.ageMonths ~/ 12;
    final months = p.ageMonths % 12;
    if (years == 0) return '$months months';
    if (months == 0) return '$years years';
    return '$years years $months months';
  }

  static String _conditions(BioProfile? p) {
    final c = p?.conditions ?? const <String>[];
    return c.isEmpty ? 'none' : c.join(', ');
  }

  static String _allowedDrugs(FirstAidEntry? e) {
    final meds = e?.medications ?? const <Medication>[];
    if (meds.isEmpty) return 'none';
    return meds.map((m) => m.name).join(', ');
  }

  static String _severity(ReplyTone t) => switch (t) {
        ReplyTone.calm => 'self-care or low-severity',
        ReplyTone.caution => 'high — needs medical attention soon',
        ReplyTone.emergency => 'emergency',
      };

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

/// Recommended sampling configuration when Gemma runs as the
/// verbalizer. Low temperature for clinical content; capped output so
/// even a runaway Gemma can't blow past the safety guard's regex
/// length-of-prose budget.
class VerbalizerSampling {
  const VerbalizerSampling({
    this.temperature = 0.2,
    this.topK = 40,
    this.topP = 0.9,
    this.maxTokens = 80,
  });

  final double temperature;
  final int topK;
  final double topP;
  final int maxTokens;

  /// Default — what we ship.
  static const VerbalizerSampling defaults = VerbalizerSampling();
}

/// Helper: in v1 we never call Gemma for low-severity replies that
/// don't have a body worth warming up (e.g. fallback "tell me more").
/// Saves load + latency for a turn that won't visibly improve.
bool shouldVerbalize(SemaReply reply) {
  // Skip empty / clearly-templated bodies.
  if (reply.body.trim().length < 20) return false;
  // Skip the greeting — already warm enough; rewriting risks drift.
  if (reply.headline.startsWith("Hi, I'm Sema")) return false;
  return true;
}

/// Convenience — same severity → tone mapping ReplyFormatter uses.
ReplyTone toneForSeverity(Severity s) => ReplyTone.fromSeverity(s);
