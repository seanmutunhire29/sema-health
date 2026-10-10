import '../domain/triage/triage_input.dart' show BioProfile;
import 'sema_reply.dart';
import 'symptom_agent.dart' show AgentTurn;

export 'symptom_agent.dart' show AgentTurn;

/// Common surface for any agent the chat screen can drive — today
/// either the deterministic [SymptomAgent] or the
/// [TranslatingSymptomAgent] wrapper that bridges non-English locales
/// via NLLB MT.
///
/// Kept intentionally narrow: only the methods the chat actually calls.
/// Both implementations stay free to add their own constructor surface
/// (engine/repo/translator/etc.) without polluting this contract.
abstract class ChatAgent {
  /// Reply Sema sends right after onboarding. Personalized when the
  /// profile carries a display name.
  SemaReply greeting(BioProfile? profile);

  /// Run a turn and stream progressive replies. Implementations decide
  /// how many events to emit per turn (the deterministic agent streams
  /// per Gemma chunk; the translating agent emits a placeholder + the
  /// final post-MT reply).
  Stream<AgentTurn> respondStream({
    required String userText,
    required BioProfile? profile,
  });

  /// Convenience: drain [respondStream] and return only the final turn.
  Future<AgentTurn> respond({
    required String userText,
    required BioProfile? profile,
  });
}
