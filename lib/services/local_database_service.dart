import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabaseService {
  LocalDatabaseService._internal();

  static final LocalDatabaseService _instance = LocalDatabaseService._internal();

  factory LocalDatabaseService() => _instance;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'anonpro.db');

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE posts (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        content TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        likes_count INTEGER DEFAULT 0,
        comments_count INTEGER DEFAULT 0,
        is_anonymous INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        is_local_only INTEGER DEFAULT 0,
        metadata TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT,
        last_message TEXT,
        last_message_at INTEGER,
        unread_count INTEGER DEFAULT 0,
        is_anonymous INTEGER DEFAULT 0,
        is_muted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT,
        sender_id TEXT,
        receiver_id TEXT,
        content TEXT,
        created_at INTEGER,
        status TEXT,
        is_deleted INTEGER DEFAULT 0,
        is_local_only INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE anonymous_interactions (
        id TEXT PRIMARY KEY,
        post_id TEXT,
        user_id TEXT,
        type TEXT,
        content TEXT,
        created_at INTEGER,
        is_deleted INTEGER DEFAULT 0,
        is_local_only INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE user_profiles (
        id TEXT PRIMARY KEY,
        username TEXT,
        display_name TEXT,
        avatar_url TEXT,
        bio TEXT,
        settings_json TEXT,
        updated_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT,
        operation TEXT,
        row_id TEXT,
        payload TEXT,
        created_at INTEGER
      )
    ''');
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete('posts');
    await db.delete('conversations');
    await db.delete('messages');
    await db.delete('anonymous_interactions');
    await db.delete('user_profiles');
    await db.delete('pending_operations');
  }

  Future<void> upsertPosts(List<Map<String, dynamic>> posts) async {
    if (posts.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final post in posts) {
      batch.insert(
        'posts',
        _normalizePost(post),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedPosts({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    return db.query(
      'posts',
      where: 'is_deleted = 0',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> upsertConversations(
    List<Map<String, dynamic>> conversations,
  ) async {
    if (conversations.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final convo in conversations) {
      batch.insert(
        'conversations',
        convo,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedConversations() async {
    final db = await database;
    return db.query(
      'conversations',
      orderBy: 'last_message_at DESC',
    );
  }

  Future<void> upsertMessages(List<Map<String, dynamic>> messages) async {
    if (messages.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final message in messages) {
      batch.insert(
        'messages',
        message,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedMessagesForConversation(
    String conversationId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    return db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> upsertAnonymousInteractions(
    List<Map<String, dynamic>> interactions,
  ) async {
    if (interactions.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final interaction in interactions) {
      batch.insert(
        'anonymous_interactions',
        interaction,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> upsertUserProfiles(
    List<Map<String, dynamic>> profiles,
  ) async {
    if (profiles.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final profile in profiles) {
      batch.insert(
        'user_profiles',
        profile,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final db = await database;
    final rows = await db.query(
      'user_profiles',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> addPendingOperation({
    required String tableName,
    required String operation,
    required String rowId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    await db.insert('pending_operations', {
      'table_name': tableName,
      'operation': operation,
      'row_id': rowId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final db = await database;
    return db.query(
      'pending_operations',
      orderBy: 'created_at ASC',
    );
  }

  Future<void> removePendingOperation(int id) async {
    final db = await database;
    await db.delete(
      'pending_operations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, dynamic> _normalizePost(Map<String, dynamic> raw) {
    final createdAt = raw['created_at'];
    final updatedAt = raw['updated_at'];

    int? toMillis(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is DateTime) return value.millisecondsSinceEpoch;
      if (value is String) {
        final dt = DateTime.tryParse(value);
        return dt?.millisecondsSinceEpoch;
      }
      return null;
    }

    return {
      'id': raw['id'],
      'user_id': raw['user_id'],
      'content': raw['content'],
      'created_at': toMillis(createdAt),
      'updated_at': toMillis(updatedAt),
      'likes_count': raw['likes_count'] ?? 0,
      'comments_count': raw['comments_count'] ?? 0,
      'is_anonymous': (raw['is_anonymous'] ?? false) ? 1 : 0,
      'is_deleted': (raw['is_deleted'] ?? false) ? 1 : 0,
      'is_local_only': (raw['is_local_only'] ?? false) ? 1 : 0,
      'metadata': raw['metadata'] == null ? null : jsonEncode(raw['metadata']),
    };
  }
}

