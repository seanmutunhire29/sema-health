import '../../ai/sema_reply.dart';

/// One row of the chat transcript, hydrated for the UI.
///
/// Sealed hierarchy mirrors the in-memory `_Msg` types the screen used
/// before persistence landed — so the rest of the chat code only had
/// to swap one source for another. The DB layer (`MessageRow`) gets
/// translated to one of these by the store.
sealed class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.createdAt,
  });

  /// Stable id from the database. The chat uses it as a list key so
  /// streaming updates don't cause widgets to drop state.
  final int id;
  final DateTime createdAt;
}

class UserChatMessage extends ChatMessage {
  const UserChatMessage({
    required super.id,
    required super.createdAt,
    required this.text,
  });
  final String text;
}

class SemaTextChatMessage extends ChatMessage {
  const SemaTextChatMessage({
    required super.id,
    required super.createdAt,
    required this.text,
  });
  final String text;
}

class SemaReplyChatMessage extends ChatMessage {
  const SemaReplyChatMessage({
    required super.id,
    required super.createdAt,
    required this.reply,
  });
  final SemaReply reply;
}

/// Stored kind strings — the database column is just a tag, the
/// hydration logic in `ConversationStore` switches on these.
class MessageKindCodec {
  const MessageKindCodec._();

  static const String userText = 'user_text';
  static const String semaText = 'sema_text';
  static const String semaReply = 'sema_reply';
}
