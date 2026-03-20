import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database_service.dart';
import '../utils/app_error_handler.dart';

class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService(this._db, this._supabaseClient) {
    _init();
  }

  final LocalDatabaseService _db;
  final SupabaseClient _supabaseClient;

  bool _isSyncing = false;
  DateTime? _lastSuccessfulSync;
  String? _lastError;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  String? get lastError => _lastError;

  void _init() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_handleConnectivityChange);
    _triggerSyncIfOnline();
  }

  Future<void> _handleConnectivityChange(
    List<ConnectivityResult> results,
  ) async {
    final hasConnection =
        results.any((result) => result != ConnectivityResult.none);
    if (!hasConnection) return;
    await triggerFullSync();
  }

  Future<void> _triggerSyncIfOnline() async {
    final results = await Connectivity().checkConnectivity();
    final hasConnection =
        results.any((result) => result != ConnectivityResult.none);
    if (hasConnection) {
      await triggerFullSync();
    }
  }

  Future<void> triggerFullSync() async {
    if (_isSyncing) return;

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      await _pushPendingOperations();
      await _pullLatestData();

      _lastSuccessfulSync = DateTime.now();
      notifyListeners();
    } catch (e) {
      _lastError = AppErrorHandler.userMessage(e);
      notifyListeners();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _pushPendingOperations() async {
    final pending = await _db.getPendingOperations();

    for (final op in pending) {
      final id = op['id'] as int;
      final tableName = op['table_name'] as String;
      final operation = op['operation'] as String;
      final payloadJson = op['payload'] as String?;

      if (payloadJson == null) {
        await _db.removePendingOperation(id);
        continue;
      }

      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

      try {
        final query = _supabaseClient.from(tableName);

        if (operation == 'insert') {
          await query.insert(payload);
        } else if (operation == 'update') {
          final rowId = op['row_id'];
          if (rowId != null) {
            await query.update(payload).eq('id', rowId);
          } else {
            await query.update(payload);
          }
        } else if (operation == 'delete') {
          final rowId = op['row_id'];
          if (rowId != null) {
            await query.delete().eq('id', rowId);
          } else {
            await query.delete();
          }
        }

        await _db.removePendingOperation(id);
      } catch (_) {}
    }
  }

  Future<void> _pullLatestData() async {
    await _syncPosts();
    await _syncConversationsAndMessages();
    await _syncAnonymousInteractions();
    await _syncProfiles();
  }

  Future<void> _syncPosts() async {
    try {
      final response = await _supabaseClient
          .from('posts')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      final posts = List<Map<String, dynamic>>.from(response as List);
      await _db.upsertPosts(posts);
    } catch (_) {}
  }

  Future<void> _syncConversationsAndMessages() async {
    try {
      final conversationsResp = await _supabaseClient
          .from('conversations')
          .select()
          .order('updated_at', ascending: false)
          .limit(200);
      final conversations =
          List<Map<String, dynamic>>.from(conversationsResp as List);
      await _db.upsertConversations(conversations);
    } catch (_) {}

    try {
      final messagesResp = await _supabaseClient
          .from('messages')
          .select()
          .order('created_at', ascending: false)
          .limit(500);
      final messages = List<Map<String, dynamic>>.from(messagesResp as List);
      await _db.upsertMessages(messages);
    } catch (_) {}
  }

  Future<void> _syncAnonymousInteractions() async {
    try {
      final response = await _supabaseClient
          .from('anonymous_interactions')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      final interactions =
          List<Map<String, dynamic>>.from(response as List);
      await _db.upsertAnonymousInteractions(interactions);
    } catch (_) {}
  }

  Future<void> _syncProfiles() async {
    try {
      final response =
          await _supabaseClient.from('profiles').select().limit(500);
      final profiles = List<Map<String, dynamic>>.from(response as List);
      await _db.upsertUserProfiles(profiles);
    } catch (_) {}
  }

  Future<void> queuePostInsert(Map<String, dynamic> post) async {
    await _db.addPendingOperation(
      tableName: 'posts',
      operation: 'insert',
      rowId: post['id']?.toString() ?? '',
      payload: post,
    );
  }

  Future<void> queueMessageInsert(Map<String, dynamic> message) async {
    await _db.addPendingOperation(
      tableName: 'messages',
      operation: 'insert',
      rowId: message['id']?.toString() ?? '',
      payload: message,
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
