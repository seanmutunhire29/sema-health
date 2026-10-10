import 'dart:convert';

import 'tools/clinical_tools.dart';

/// Wire-format helpers for Gemma-side function calling.
///
/// We don't depend on flutter_gemma's native tool-call API because the
/// surface is still in flux upstream and we want to be portable across
/// runtimes (MediaPipe today, llama.cpp / Ollama tomorrow). Instead we
/// teach Gemma a tiny plain-text protocol via the system prompt and parse
/// the same markup ourselves.
///
/// Markup:
///   `<tool_call>{"name":"<tool>", "args":{...}}</tool_call>`
///   `<tool_result name="<tool>">{ ... json ... }</tool_result>`
///
/// This is robust to streamed output: we accumulate tokens until a
/// closing `</tool_call>` tag is seen, parse the JSON, dispatch the
/// tool, then feed the result back via `<tool_result>` and resume
/// generation.
class ToolCall {
  const ToolCall({required this.name, required this.args, required this.raw});

  /// Tool name, matched against [Tool.name].
  final String name;

  /// Parsed JSON arguments. Always a Map (possibly empty).
  final Map<String, Object?> args;

  /// The exact substring (with delimiters) that was parsed. Useful for
  /// stripping the markup out of streamed text before showing it to the
  /// user.
  final String raw;

  Map<String, Object?> toJson() => {'name': name, 'args': args};
}

/// Open/close tags for the tool-call markup.
const String _openCall = '<tool_call>';
const String _closeCall = '</tool_call>';

/// Look for a complete `<tool_call>...</tool_call>` block in [buffer].
/// Returns null when the buffer is partial (still streaming).
ToolCall? extractToolCall(String buffer) {
  final start = buffer.indexOf(_openCall);
  if (start < 0) return null;
  final end = buffer.indexOf(_closeCall, start + _openCall.length);
  if (end < 0) return null;

  final raw = buffer.substring(start, end + _closeCall.length);
  final inner = buffer.substring(start + _openCall.length, end).trim();

  try {
    final decoded = jsonDecode(inner);
    if (decoded is! Map) return null;
    final name = decoded['name'];
    if (name is! String) return null;
    final argsNode = decoded['args'];
    final args = argsNode is Map
        ? argsNode.map((k, v) => MapEntry(k.toString(), v))
        : <String, Object?>{};
    return ToolCall(name: name, args: args, raw: raw);
  } on FormatException {
    // Gemma emitted partial / malformed JSON. Treat as no call so the
    // dispatcher keeps streaming; the buffer may still complete validly
    // as more tokens arrive.
    return null;
  }
}

/// Drop the matched tool-call markup from [buffer], returning the text
/// that should be shown to the user (everything before the call).
String stripToolCall(String buffer, ToolCall call) {
  final idx = buffer.indexOf(call.raw);
  if (idx < 0) return buffer;
  return buffer.substring(0, idx);
}

/// Encode a tool result for re-injection into the prompt.
String encodeToolResult({required String name, required String resultJson}) {
  return '<tool_result name="$name">$resultJson</tool_result>';
}

/// Render the system-prompt section that teaches Gemma the protocol +
/// the available tools. Keep this short — every token costs latency on
/// edge devices.
String renderToolPalette(List<Tool> tools) {
  final buf = StringBuffer()
    ..writeln('You can call tools to ground your answer in the clinical '
        'knowledge graph. To call a tool, output a single line:')
    ..writeln('<tool_call>{"name":"<tool>","args":{...}}</tool_call>')
    ..writeln('Stop generating after the closing tag and wait for the '
        '<tool_result>. Then continue your answer using the result.')
    ..writeln('Available tools:');
  for (final t in tools) {
    buf
      ..writeln('- ${t.name}: ${t.description}')
      ..writeln('  schema: ${jsonEncode(t.parametersSchema)}');
  }
  buf.writeln(
    'Rules: never invent symptoms, severities, or steps the tools did '
    'not return. If no tool fits, ask a clarifying question instead.',
  );
  return buf.toString();
}
