import 'dart:async';

import '../data/seed/first_aid_models.dart';
import '../domain/triage/triage_input.dart';
import 'llm.dart';
import 'sema_reply.dart';
import 'system_prompt.dart';

/// Rewrites a [SemaReply]'s `body` paragraph in a warmer voice.
///
/// Streaming model: every implementation returns a `Stream<SemaReply>`
/// where each event is a snapshot of the reply with the current
/// (possibly partial) body. The final event is the polished result
/// (post-processing already applied). The deterministic path collapses
/// to a single-event stream.
abstract class Verbalizer {
  /// Stream progressive snapshots of the reply. Concrete implementations
  /// must:
  /// - emit at least one event,
  /// - close the stream (no infinite emission),
  /// - never throw — failures fall through to the input reply.
  Stream<SemaReply> verbalizeStream({
    required SemaReply reply,
    required FirstAidEntry? matchedEntry,
    required BioProfile? profile,
    required String userText,
  });

  /// Convenience: drain the stream to its final emission. Used by tests
  /// and any non-streaming caller.
  Future<SemaReply> verbalize({
    required SemaReply reply,
    required FirstAidEntry? matchedEntry,
    required BioProfile? profile,
    required String userText,
  }) async {
    SemaReply last = reply;
    await for (final r in verbalizeStream(
      reply: reply,
      matchedEntry: matchedEntry,
      profile: profile,
      userText: userText,
    )) {
      last = r;
    }
    return last;
  }
}

/// Pass-through. Used when no Gemma model is available on device or
/// when the verbalizer is disabled (settings). Emits the input reply
/// once and completes.
class NullVerbalizer implements Verbalizer {
  const NullVerbalizer();

  @override
  Stream<SemaReply> verbalizeStream({
    required SemaReply reply,
    required FirstAidEntry? matchedEntry,
    required BioProfile? profile,
    required String userText,
  }) {
    return Stream.value(reply);
  }

  @override
  Future<SemaReply> verbalize({
    required SemaReply reply,
    required FirstAidEntry? matchedEntry,
    required BioProfile? profile,
    required String userText,
  }) async {
    return reply;
  }
}

/// Gemma-backed verbalizer. The LLM only rewrites the prose `body` —
/// `headline`, `steps`, `donts`, and `cta` are surfaced verbatim from
/// the deterministic pipeline. The architecture's "LLM drives
/// expression, not triage" principle is enforced *here*, in code, so a
/// future prompt regression can't escalate it.
class GemmaVerbalizer implements Verbalizer {
  GemmaVerbalizer({
    required this.llm,
    this.sampling = VerbalizerSampling.defaults,
    this.timeout = const Duration(seconds: 8),
    this.minIntermediateChars = 12,
    this.intermediateThrottle = const Duration(milliseconds: 60),
  });

  final Llm llm;
  final VerbalizerSampling sampling;

  /// Hard ceiling on how long we wait for tokens before falling
  /// through. Mid-tier devices on Gemma 3n int4 finish a 60-word reply
  /// in ~2-3 s; 8 s gives headroom without blocking the chat.
  final Duration timeout;

  /// Don't emit a streaming snapshot until we have at least this many
  /// chars — saves the chat from rebuilding for a single token.
  final int minIntermediateChars;

  /// Minimum gap between intermediate emissions. The final emission
  /// always fires regardless of throttle.
  final Duration intermediateThrottle;

  @override
  Future<SemaReply> verbalize({
    required SemaReply reply,
    required FirstAidEntry? matchedEntry,
    required BioProfile? profile,
    required String userText,
  }) async {
    SemaReply last = reply;
    await for (final r in verbalizeStream(
      reply: reply,
      matchedEntry: matchedEntry,
      profile: profile,
      userText: userText,
    )) {
      last = r;
    }
    return last;
  }

  @override
  Stream<SemaReply> verbalizeStream({
    required SemaReply reply,
    required FirstAidEntry? matchedEntry,
    required BioProfile? profile,
    required String userText,
  }) async* {
    if (!shouldVerbalize(reply)) {
      yield reply;
      return;
    }

    SemaReply last = reply;
    try {
      if (!llm.isLoaded) await llm.load();
      final userPrompt = VerbalizePrompt.buildUserMessage(
        userText: userText,
        reply: reply,
        entry: matchedEntry,
        profile: profile,
      );

      final stream = llm
          .generate(
            userPrompt,
            systemPrompt: VerbalizePrompt.systemInstruction,
            maxTokens: sampling.maxTokens,
            temperature: sampling.temperature,
          )
          .timeout(timeout);

      const maxChars = 2000;
      final buf = StringBuffer();
      DateTime? lastEmit;

      await for (final chunk in stream) {
        buf.write(chunk);
        if (buf.length > maxChars) break;

        final body = buf.toString().trimLeft();
        if (body.length < minIntermediateChars) continue;

        final now = DateTime.now();
        if (lastEmit != null &&
            now.difference(lastEmit).compareTo(intermediateThrottle) < 0) {
          continue;
        }
        lastEmit = now;
        last = reply.copyWith(body: body);
        yield last;
      }

      final cleaned = _postProcess(buf.toString());
      if (cleaned == null) {
        // Gemma produced nothing usable; fall through to original.
        if (last == reply) yield reply;
        return;
      }
      final finalReply = reply.copyWith(body: cleaned);
      // Always emit the polished version — even if it equals the last
      // intermediate, the chat treats this stream's last event as the
      // settled reply.
      yield finalReply;
    } on TimeoutException {
      // Settle on whatever we'd accumulated; if nothing, send original.
      if (last == reply) yield reply;
      return;
    } catch (_) {
      // Any failure (model missing, OOM, decoder hiccup) falls back to
      // the deterministic reply. The chat must never be blocked by the
      // LLM — that's the entire point of the architecture's split.
      if (last == reply) yield reply;
      return;
    }
  }

  /// Strip stray quotes, leading "Sema:"-style framing, blank trailing
  /// lines. Returns null when the result is empty or obviously broken,
  /// signaling the caller to fall through to the original.
  static String? _postProcess(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Remove a single set of wrapping quotes if Gemma added them.
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith('“') && s.endsWith('”'))) {
      s = s.substring(1, s.length - 1).trim();
    }
    // Strip "Sema:" / "Assistant:" leading framing.
    s = s.replaceFirst(
      RegExp(r'^(sema|assistant)\s*:\s*', caseSensitive: false),
      '',
    );
    // Collapse extra blank lines.
    s = s.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    if (s.length < 8) return null;
    // Hard length cap — the regex blocklist runs after, but we don't
    // want a megaparagraph reaching the bubble even if it's clean.
    if (s.length > 600) s = '${s.substring(0, 600).trimRight()}…';
    return s;
  }
}
