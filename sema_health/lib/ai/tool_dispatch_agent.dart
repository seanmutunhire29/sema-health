import 'llm.dart';
import 'tool_protocol.dart';
import 'tools/clinical_tools.dart';

/// Multi-turn LLM loop with native function calling against the clinical
/// KG. Used as the *fallback* when the deterministic triage engine
/// doesn't have a rule for the user's turn — Gemma can then look up
/// candidate entries and ground its reply in real KG data instead of
/// hallucinating.
///
/// Loop:
///   1. Render system prompt = persona + tool palette.
///   2. Stream Gemma's response.
///   3. As tokens arrive, watch for a complete `<tool_call>` block.
///   4. On call: stop streaming, dispatch to the matching [Tool],
///      append the result as `<tool_result>`, and resume generation
///      from the same conversation.
///   5. Cap at [maxIterations] to bound latency / token spend.
///
/// The agent yields user-facing text incrementally — any tokens before
/// a tool call go to the chat bubble immediately so the user sees
/// progress; the markup itself is stripped before it reaches the UI.
class ToolDispatchAgent {
  ToolDispatchAgent({
    required this.llm,
    required this.tools,
    this.maxIterations = 3,
    this.maxTokensPerStep = 256,
    this.temperature = 0.4,
  });

  final Llm llm;
  final List<Tool> tools;
  final int maxIterations;
  final int maxTokensPerStep;
  final double temperature;

  /// Stream the assistant's reply for [userText]. The caller appends
  /// each emitted chunk to a Sema-side bubble.
  Stream<String> reply({
    required String userText,
    String? extraSystemContext,
  }) async* {
    if (!llm.isLoaded) {
      // No model loaded — surface a sentinel so the caller can fall back
      // to the deterministic agent or render an offline-error bubble.
      throw StateError(
        'ToolDispatchAgent: llm.load() must be called first.',
      );
    }

    final tableByName = {for (final t in tools) t.name: t};
    final systemPrompt = _buildSystemPrompt(extraSystemContext);

    var conversation = StringBuffer()..writeln('User: $userText')
      ..write('Assistant: ');

    for (var iter = 0; iter < maxIterations; iter++) {
      final buffer = StringBuffer();
      var emittedUpTo = 0; // chars of `buffer` already yielded to the UI
      ToolCall? call;

      await for (final chunk in llm.generate(
        conversation.toString(),
        systemPrompt: systemPrompt,
        maxTokens: maxTokensPerStep,
        temperature: temperature,
      )) {
        buffer.write(chunk);
        // Watch for a complete tool-call block. Until we see one, stream
        // the un-markup'd prefix to the user so they get tokens live.
        call = extractToolCall(buffer.toString());
        if (call != null) {
          // Yield only the prose that came before the call; stop the
          // inner stream by breaking — the model will keep going if we
          // re-prompt below.
          final preCall = stripToolCall(buffer.toString(), call);
          final unsent = preCall.substring(emittedUpTo);
          if (unsent.isNotEmpty) yield unsent;
          break;
        }
        // No call yet: forward whatever new tokens arrived this round.
        final current = buffer.toString();
        final unsent = current.substring(emittedUpTo);
        if (unsent.isNotEmpty) {
          yield unsent;
          emittedUpTo = current.length;
        }
      }

      if (call == null) {
        // Stream ended without a tool call — we're done.
        return;
      }

      final tool = tableByName[call.name];
      final resultJson = tool == null
          ? '{"error":"unknown tool ${call.name}"}'
          : await tool.call(call.args);

      // Append the model's call + the tool result and re-prompt. Gemma
      // will keep writing the answer using the result.
      conversation
        ..write(call.raw)
        ..write(encodeToolResult(name: call.name, resultJson: resultJson));
    }
  }

  String _buildSystemPrompt(String? extra) {
    final buf = StringBuffer()
      ..writeln(
        'You are Sema — a warm, attentive, offline-first health companion. '
        'Sound like a thoughtful friend who happens to know first aid. '
        'Talk to the person, not at them: acknowledge what they said, use '
        '"you" and "let\'s" where it fits, keep sentences short.',
      )
      ..writeln()
      ..writeln(
        'Hard limits — non-negotiable:',
      )
      ..writeln(
        '- Never diagnose with certainty ("sounds like" / "could be", '
        'never "you have").',
      )
      ..writeln('- Never invent dosages.')
      ..writeln(
        '- Never name a medication unless a tool result lists it.',
      )
      ..writeln(
        '- If anything you hear could be life-threatening, your FIRST '
        'sentence tells the person to seek emergency care — warmth comes '
        'after the action, never before.',
      )
      ..writeln()
      ..writeln(renderToolPalette(tools));
    if (extra != null && extra.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Context for this conversation:')
        ..writeln(extra);
    }
    return buf.toString();
  }
}
