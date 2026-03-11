import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../models/confession_room_model.dart';
import '../../utils/constants.dart';
import 'confession_rooms_screen.dart';

class DiscoverRoomsScreen extends StatefulWidget {
  const DiscoverRoomsScreen({super.key});

  @override
  State<DiscoverRoomsScreen> createState() => _DiscoverRoomsScreenState();
}

class _DiscoverRoomsScreenState extends State<DiscoverRoomsScreen> {
  List<ConfessionRoomModel> _rooms = [];
  bool _isLoading = true;
  int _newRoomsCount = 0;
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _loadAvailableRooms();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    final supabase = Supabase.instance.client;
    _subscription = supabase
        .channel('confession_rooms_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'confession_rooms',
          callback: (payload) {
            // New room created
            if (mounted) {
              setState(() => _newRoomsCount++);
              debugPrint('New room created! Count: $_newRoomsCount');
              // Reload and show notification
              _loadAvailableRooms();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.new_releases_rounded,
                          color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New room created! $_newRoomsCount available',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppConstants.primaryBlue,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadAvailableRooms() async {
    try {
      // Get all active rooms from database
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('confession_rooms')
          .select()
          .eq('is_active', true)
          .gt('expires_at',
              DateTime.now().toIso8601String()) // Only non-expired rooms
          .order('created_at', ascending: false);

      final rooms = (response as List)
          .map((data) => ConfessionRoomModel.fromJson(data))
          .toList();

      if (mounted) {
        setState(() {
          _rooms = rooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading rooms: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  String _getTimeRemaining(DateTime expiresAt) {
    final now = DateTime.now();
    final remaining = expiresAt.difference(now);

    if (remaining.inSeconds <= 0) {
      return 'Expired';
    } else if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left';
    } else {
      return '${remaining.inMinutes}m left';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Discover Rooms'),
        backgroundColor: AppConstants.black,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : _rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 64,
                        color: AppConstants.textSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No rooms available right now',
                        style: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Check back later to join anonymous chat rooms',
                        style: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAvailableRooms,
                  color: AppConstants.primaryBlue,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rooms.length,
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      final timeRemaining = _getTimeRemaining(room.expiresAt);
                      final isExpired = room.isExpired;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppConstants.primaryBlue.withOpacity(0.1),
                              AppConstants.primaryBlue.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppConstants.primaryBlue.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppConstants.primaryBlue,
                                  AppConstants.primaryBlue.withOpacity(0.5),
                                ],
                              ),
                            ),
                            child: const Icon(
                              Icons.chat_bubble_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            room.roomName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 14,
                                    color: isExpired
                                        ? AppConstants.red
                                        : AppConstants.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    timeRemaining,
                                    style: TextStyle(
                                      color: isExpired
                                          ? AppConstants.red
                                          : AppConstants.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: !isExpired
                              ? ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (ctx) =>
                                            ConfessionRoomChatScreen(
                                          roomId: room.id,
                                          roomName: room.roomName,
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppConstants.primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text('Join'),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppConstants.red.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Expired',
                                    style: TextStyle(
                                      color: AppConstants.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
