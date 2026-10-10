/// Render-time text scrubber for chat output.
///
/// Em dashes look out of place in casual chat copy and the LLM tends to
/// over-use them. We strip at render so the rule covers both canned
/// strings and live LLM tokens without round-tripping through the data
/// model.
///
/// Substitutions:
/// - ` — ` (spaced em dash) → `, ` so the sentence still reads as a clause break.
/// - bare `—` → `-` (regular hyphen) for compound words.
/// - en dash `–` gets the same treatment.
/// Also collapses any duplicate spaces created along the way.
String stripEmDashes(String input) {
  if (input.isEmpty) return input;
  var out = input.replaceAll(' — ', ', ').replaceAll(' – ', ', ');
  out = out.replaceAll('—', '-').replaceAll('–', '-');
  return out.replaceAll(RegExp(r' {2,}'), ' ');
}
