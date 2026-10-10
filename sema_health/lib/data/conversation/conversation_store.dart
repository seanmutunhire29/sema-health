import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/sema_reply.dart';
import '../../ai/sema_reply_serde.dart';
import '../db/app_database.dart';
import 'chat_message.dart';

/// High-level API the chat screen reads.
///
/// Composes [AppDatabase] (the storage layer) with the SemaReply
/// serde (the JSON shape) and the [ChatMessage] sealed hierarchy
/// (what the UI consumes). Everything below this layer is a
/// swap-target: when Drift+SQLCipher lands, only `app_database.dart`
/// changes.
///
/// The store is process-wide. It owns one [AppDatabase] handle which
/// is shared across the app — opening sqflite multiple times for the
/// same file is allowed but undermines the per-database mutex SQLite
/// uses for write serialization. Single shared handle = simplest model.
class ConversationStore {
  ConversationStore._(this._db);

  final AppDatabase _db;

  /// The active conversation id we're appending into. Created lazily
  /// the first time the chat sends a message; resumed on subsequent
  /// chat-screen entries.
  int? _activeId;
  int? get activeId => _activeId;

  /// Notifies non-stream consumers (the journal list) that a write
  /// happened so they can refetch. The chat transcript itself uses the
  /// per-conversation reactive stream from [watch], so this is mainly
  /// for screens that show *across* conversations and don't have a
  /// single id to subscribe to.
  ///
  /// Usage: `store.changes.addListener(...)` in initState, remove in
  /// dispose, refetch the list when notified.
  Listenable get changes => _changes;
  final _ChangePulse _changes = _ChangePulse();

  static ConversationStore? _instance;

  /// Open the singleton. Idempotent — repeated calls return the same
  /// instance. The chat screen kicks this off in its bootstrap.
  static Future<ConversationStore> open() async {
    if (_instance != null) return _instance!;
    final db = await AppDatabase.open();
    _instance = ConversationStore._(db);
    return _instance!;
  }

  /// Returns the current active conversation, creating one if there
  /// is none. Resumes the most recent on cold start so a user who
  /// closed the app mid-emergency comes back to the same transcript.
  Future<int> getOrCreateActive({String? profileLabel}) async {
    if (_activeId != null) return _activeId!;
    final recent = await _db.mostRecentConversation();
    if (recent != null) {
      _activeId = recent.id;
      return _activeId!;
    }
    _activeId = await _db.startConversation(profileLabel: profileLabel);
    return _activeId!;
  }

  /// Begin a fresh conversation. Used by the "New chat" affordance.
  ///
  /// Pulses [changes] so the journal — which listens via the
  /// IndexedStack lifecycle and otherwise wouldn't know — refreshes
  /// and surfaces the prior conversation as a saved entry. Without
  /// this pulse, users tap "New chat" and (correctly) think their
  /// previous session vanished, because the journal still shows the
  /// stale list.
  Future<int> startNew({String? profileLabel}) async {
    _activeId = await _db.startConversation(profileLabel: profileLabel);
    _changes.pulse();
    return _activeId!;
  }

  // ─── Append API ─────────────────────────────────────────────────
  //
  // Each append returns the new row id so the caller can track which
  // bubble was just persisted (useful for the streaming reply that
  // mutates after the initial insert).

  Future<int> appendUserMessage({
    required int conversationId,
    required String text,
  }) async {
    final id = await _db.appendMessage(
      conversationId: conversationId,
      kind: MessageKindCodec.userText,
      textBody: text,
    );
    _changes.pulse();
    return id;
  }

  Future<int> appendSemaText({
    required int conversationId,
    required String text,
  }) async {
    final id = await _db.appendMessage(
      conversationId: conversationId,
      kind: MessageKindCodec.semaText,
      textBody: text,
    );
    _changes.pulse();
    return id;
  }

  Future<int> appendSemaReply({
    required int conversationId,
    required SemaReply reply,
  }) async {
    final id = await _db.appendMessage(
      conversationId: conversationId,
      kind: MessageKindCodec.semaReply,
      replyPayload: reply.toJsonString(),
    );
    _changes.pulse();
    return id;
  }

  /// Update an already-persisted Sema reply with a new payload.
  /// Used for the streaming verbalizer / tool-dispatch path: we
  /// insert a placeholder reply on the first emission, then update
  /// the payload as Gemma writes more tokens.
  Future<void> updateSemaReply({
    required int conversationId,
    required int messageId,
    required SemaReply reply,
  }) async {
    await _db.updateLastReplyPayload(
      conversationId: conversationId,
      messageId: messageId,
      replyPayload: reply.toJsonString(),
    );
    _changes.pulse();
  }

  // ─── Reads ─────────────────────────────────────────────────────

  /// Reactive transcript. The first event is the current contents;
  /// subsequent events fire after every append / update / clear.
  Stream<List<ChatMessage>> watch(int conversationId) {
    return _db
        .watchMessages(conversationId)
        .map((rows) => [for (final r in rows) _hydrate(r)])
        .map((list) => List<ChatMessage>.unmodifiable(list));
  }

  /// One-shot read — used by tests and any non-reactive caller.
  Future<List<ChatMessage>> read(int conversationId) async {
    final rows = await _db.messages(conversationId);
    return [for (final r in rows) _hydrate(r)];
  }

  /// List recent conversations, most recent first. Backs the journal
  /// list view. Limit is a soft cap; the journal screen can request
  /// more if it ever needs pagination.
  Future<List<ConversationRow>> recentConversations({int limit = 50}) =>
      _db.recentConversations(limit: limit);

  /// Cheap summary used by the journal list-view tile. Reads the
  /// transcript and returns a tuple of (first sema reply, transcript
  /// length). Returns nulls for an empty conversation. Stays a single
  /// SQL query per conversation; list-view sizes are small (≤50) so
  /// the N+1 cost is negligible vs. the polish a headline preview adds.
  Future<({SemaReply? firstReply, int turnCount})> summarize(
    int conversationId,
  ) async {
    final messages = await read(conversationId);
    SemaReply? first;
    for (final m in messages) {
      if (m is SemaReplyChatMessage) {
        first = m.reply;
        break;
      }
    }
    return (firstReply: first, turnCount: messages.length);
  }

  /// Wipe a conversation. Honored by the architecture's M3 emergency
  /// wipe; until then this is the "Start new chat" implementation.
  Future<void> deleteConversation(int conversationId) async {
    await _db.deleteConversation(conversationId);
    if (_activeId == conversationId) _activeId = null;
    _changes.pulse();
  }

  // ─── Hydration ────────────────────────────────────────────────

  /// `ChangeNotifier`'s `notifyListeners` is `@protected`, so we expose a
  /// thin subclass with a public pulse() method.
  ChatMessage _hydrate(MessageRow r) {
    switch (r.kind) {
      case MessageKindCodec.userText:
        return UserChatMessage(
          id: r.id,
          createdAt: r.createdAt,
          text: r.textBody ?? '',
        );
      case MessageKindCodec.semaText:
        return SemaTextChatMessage(
          id: r.id,
          createdAt: r.createdAt,
          text: r.textBody ?? '',
        );
      case MessageKindCodec.semaReply:
        return SemaReplyChatMessage(
          id: r.id,
          createdAt: r.createdAt,
          reply: r.replyPayload == null
              ? const SemaReply(
                  tone: ReplyTone.calm,
                  headline: '',
                  body: '',
                )
              : semaReplyFromJsonString(r.replyPayload!),
        );
      default:
        // Unknown kind — fall back to a neutral text message rather
        // than crash. Keeps the chat resilient to schema additions.
        return SemaTextChatMessage(
          id: r.id,
          createdAt: r.createdAt,
          text: r.textBody ?? '',
        );
    }
  }
}

/// Subclass exposing a public pulse() — `notifyListeners` is `@protected`.
class _ChangePulse extends ChangeNotifier {
  void pulse() => notifyListeners();
}
