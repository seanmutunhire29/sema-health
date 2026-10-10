import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// On-device persistence for the chat transcript.
///
/// v1 ships on raw `sqflite` to avoid codegen during the demo cycle.
/// The M1 migration target is **Drift over SQLCipher** per
/// `ARCHITECTURE/06-implementation.md`:
///
/// - Drift gives typed CRUD + reactive streams (we approximate the
///   reactive part below with a `StreamController` per watcher).
/// - SQLCipher encrypts the file on disk, with the passphrase stored in
///   `flutter_secure_storage` (not yet wired).
///
/// The store layer in `lib/data/conversation/conversation_store.dart`
/// is the only consumer. When we swap to Drift, only this file
/// changes; the store's API stays identical.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// One controller per active conversation watcher. We push a fresh
  /// list-of-rows down each controller after every write, so a screen
  /// holding `watchMessages(id)` sees inserts immediately without
  /// polling. This is the v1 stand-in for Drift's `select(...).watch()`
  /// — same external shape (`Stream<List<MessageRow>>`).
  final Map<int, _MessagesNotifier> _watchers = {};

  // ─── Lifecycle ─────────────────────────────────────────────────

  static const _dbFileName = 'sema.db';
  static const _schemaVersion = 1;

  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbFileName);
    final db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) async {
        // Foreign keys ON; SQLite ships them off by default.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _ensureSchema,
      onOpen: (db) async {
        // Self-heal against stale dev databases: if a previous build
        // wrote a `sema.db` with a different shape, `onCreate` won't
        // re-run because the file exists. Idempotent CREATE TABLE IF
        // NOT EXISTS calls bring missing tables back, so the next open
        // succeeds without forcing a reinstall.
        await _ensureSchema(db, _schemaVersion);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 is the first version; this branch exists for the
        // M1-Drift migration's eventual onUpgrade call. Today it just
        // ensures the schema is current.
        await _ensureSchema(db, newVersion);
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> _ensureSchema(Database db, int _) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_label   TEXT,
        started_at      INTEGER NOT NULL,
        last_activity_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
        kind            TEXT NOT NULL,
        text_body       TEXT,
        reply_payload   TEXT,
        created_at      INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conv_created
      ON messages(conversation_id, created_at)
    ''');
  }

  Future<void> close() async {
    for (final w in _watchers.values) {
      await w.close();
    }
    _watchers.clear();
    await _db.close();
  }

  // ─── Conversations ─────────────────────────────────────────────

  Future<int> startConversation({String? profileLabel}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert('conversations', {
      'profile_label': profileLabel,
      'started_at': now,
      'last_activity_at': now,
    });
  }

  Future<ConversationRow?> mostRecentConversation() async {
    final rows = await _db.query(
      'conversations',
      orderBy: 'last_activity_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ConversationRow._fromMap(rows.first);
  }

  Future<List<ConversationRow>> recentConversations({int limit = 20}) async {
    final rows = await _db.query(
      'conversations',
      orderBy: 'last_activity_at DESC',
      limit: limit,
    );
    return [for (final r in rows) ConversationRow._fromMap(r)];
  }

  /// Wipe a conversation and every message under it. Used by the
  /// "clear chat" action and by the architecture's biometric-locked
  /// emergency wipe (M3).
  Future<void> deleteConversation(int conversationId) async {
    await _db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    // FK cascade handles messages. Notify any open watchers.
    final notifier = _watchers[conversationId];
    if (notifier != null) {
      notifier.notify(const []);
    }
  }

  // ─── Messages ──────────────────────────────────────────────────

  Future<int> appendMessage({
    required int conversationId,
    required String kind,
    String? textBody,
    String? replyPayload,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db.insert('messages', {
      'conversation_id': conversationId,
      'kind': kind,
      'text_body': textBody,
      'reply_payload': replyPayload,
      'created_at': now,
    });
    await _db.update(
      'conversations',
      {'last_activity_at': now},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    await _refreshWatcher(conversationId);
    return id;
  }

  Future<void> updateLastReplyPayload({
    required int conversationId,
    required int messageId,
    required String replyPayload,
  }) async {
    await _db.update(
      'messages',
      {'reply_payload': replyPayload},
      where: 'id = ? AND conversation_id = ?',
      whereArgs: [messageId, conversationId],
    );
    await _refreshWatcher(conversationId);
  }

  Future<List<MessageRow>> messages(int conversationId) async {
    final rows = await _db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC, id ASC',
    );
    return [for (final r in rows) MessageRow._fromMap(r)];
  }

  /// Reactive view of a conversation's messages. The first event is the
  /// current contents; subsequent events fire after every insert /
  /// update / delete that touches this conversation.
  ///
  /// This is the v1 stand-in for `select(...).watch()` in Drift. The
  /// implementation pushes a fresh list down a [StreamController] from
  /// inside [appendMessage] / [updateLastReplyPayload]. Listeners share
  /// one controller per conversation.
  Stream<List<MessageRow>> watchMessages(int conversationId) {
    final notifier =
        _watchers.putIfAbsent(conversationId, () => _MessagesNotifier());
    // Seed the new subscriber with the current state on the next tick.
    Future<void>(() async {
      final rows = await messages(conversationId);
      notifier.notify(rows);
    });
    return notifier.stream;
  }

  Future<void> _refreshWatcher(int conversationId) async {
    final notifier = _watchers[conversationId];
    if (notifier == null) return;
    final rows = await messages(conversationId);
    notifier.notify(rows);
  }
}

/// Per-conversation broadcast pipe. We use a broadcast controller so a
/// new subscriber can attach mid-flight (e.g. when the chat screen
/// rebuilds after a hot-reload) without dropping the stream.
class _MessagesNotifier {
  _MessagesNotifier() : _ctrl = StreamController<List<MessageRow>>.broadcast();

  final StreamController<List<MessageRow>> _ctrl;
  List<MessageRow> _last = const [];

  Stream<List<MessageRow>> get stream async* {
    // Re-emit the last known value to new subscribers so they don't
    // wait for the next write to render anything.
    yield _last;
    yield* _ctrl.stream;
  }

  void notify(List<MessageRow> rows) {
    _last = rows;
    if (!_ctrl.isClosed) _ctrl.add(rows);
  }

  Future<void> close() => _ctrl.close();
}

// ─── Row types ────────────────────────────────────────────────────

class ConversationRow {
  ConversationRow({
    required this.id,
    required this.startedAt,
    required this.lastActivityAt,
    this.profileLabel,
  });

  factory ConversationRow._fromMap(Map<String, Object?> m) {
    return ConversationRow(
      id: m['id']! as int,
      profileLabel: m['profile_label'] as String?,
      startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at']! as int),
      lastActivityAt:
          DateTime.fromMillisecondsSinceEpoch(m['last_activity_at']! as int),
    );
  }

  final int id;
  final String? profileLabel;
  final DateTime startedAt;
  final DateTime lastActivityAt;
}

class MessageRow {
  MessageRow({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.createdAt,
    this.textBody,
    this.replyPayload,
  });

  factory MessageRow._fromMap(Map<String, Object?> m) {
    return MessageRow(
      id: m['id']! as int,
      conversationId: m['conversation_id']! as int,
      kind: m['kind']! as String,
      textBody: m['text_body'] as String?,
      replyPayload: m['reply_payload'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int),
    );
  }

  final int id;
  final int conversationId;

  /// One of the [MessageKindCodec] strings. The store layer maps these
  /// to a typed `ChatMessage` for the UI.
  final String kind;
  final String? textBody;

  /// JSON-serialised SemaReply (when [kind] is sema_structured).
  final String? replyPayload;
  final DateTime createdAt;
}
