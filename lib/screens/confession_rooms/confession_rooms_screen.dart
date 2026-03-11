import 'package:flutter/material.dart';
import '../../models/confession_room_model.dart';
import '../../services/confession_rooms_service.dart';
import '../../utils/constants.dart';

class ConfessionRoomsScreen extends StatefulWidget {
  final String userId;
  final String? initialRoomId;

  const ConfessionRoomsScreen({
    super.key,
    required this.userId,
    this.initialRoomId,
  });

  @override
  State<ConfessionRoomsScreen> createState() => _ConfessionRoomsScreenState();
}

class _ConfessionRoomsScreenState extends State<ConfessionRoomsScreen> {
  final ConfessionRoomsService _roomsService = ConfessionRoomsService();
  List<ConfessionRoomModel> _rooms = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRooms();

    // If initialRoomId is provided, navigate to that room after loading
    if (widget.initialRoomId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToInitialRoom();
      });
    }
  }

  Future<void> _navigateToInitialRoom() async {
    if (widget.initialRoomId == null) return;

    try {
      final room = await _roomsService.getRoom(widget.initialRoomId!);
      if (room != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => ConfessionRoomChatScreen(
              roomId: room.id,
              roomName: room.roomName,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error navigating to room: $e');
    }
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    try {
      final rooms = await _roomsService.getUserRooms(widget.userId);
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rooms: $e')),
        );
      }
    }
  }

  void _showCreateRoomDialog() {
    final nameController = TextEditingController();
    int durationMinutes = 60;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppConstants.darkGray,
          title: const Text(
            'Create Confession Room',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Room name...',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    border: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: AppConstants.darkGray),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Duration (minutes):',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: durationMinutes,
                  onChanged: (v) {
                    setState(() => durationMinutes = v ?? 60);
                  },
                  isExpanded: true,
                  dropdownColor: AppConstants.darkGray,
                  items: [15, 30, 60, 120, 240]
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            '$d minutes',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppConstants.textSecondary),
              ),
            ),
            GestureDetector(
              onTap: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    await _roomsService.createRoom(
                      creatorId: widget.userId,
                      roomName: nameController.text,
                      durationMinutes: durationMinutes,
                    );
                    if (mounted) {
                      Navigator.pop(ctx);
                      _loadRooms();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Room created!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error creating room: $e'),
                          backgroundColor: AppConstants.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppConstants.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        title: const Text(
          'Confession Rooms',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showCreateRoomDialog,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppConstants.primaryBlue),
              ),
            )
          : _rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: AppConstants.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No active rooms',
                        style: TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
ElevatedButton.icon(
  onPressed: _showCreateRoomDialog,
  icon: const Icon(Icons.add),
  label: const Text('Create Room'),
  style: ElevatedButton.styleFrom(
    backgroundColor: AppConstants.primaryBlue,
    foregroundColor: Colors.white, // fixes invisible text
  ),
),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rooms.length,
                  itemBuilder: (ctx, idx) {
                    final room = _rooms[idx];
                    final timeRemaining = room.timeRemaining;
                    final hours = timeRemaining.inHours;
                    final minutes = timeRemaining.inMinutes % 60;

                    return Card(
                      color: AppConstants.darkGray,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    room.roomName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!room.isExpired)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppConstants.primaryBlue
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      room.isExpired
                                          ? 'Expired'
                                          : '${hours}h ${minutes}m left',
                                      style: const TextStyle(
                                        color: AppConstants.primaryBlue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Created: ${room.createdAt.toString().split('.')[0]}',
                              style: const TextStyle(
                                color: AppConstants.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (!room.isExpired)
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        // Navigate to room chat
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
                                        backgroundColor:
                                            AppConstants.primaryBlue,
                                      ),
                                      child: const Text('Join Room'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: AppConstants.darkGray,
                                          title: const Text('Close Room', style: TextStyle(color: Colors.white)),
                                          content: const Text('Are you sure you want to close this room?', style: TextStyle(color: AppConstants.textSecondary)),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('Cancel', style: TextStyle(color: AppConstants.textSecondary)),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text('Close', style: TextStyle(color: AppConstants.red)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        try {
                                          await _roomsService.closeRoom(room.id);
                                          _loadRooms();
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Error closing room: $e'),
                                                backgroundColor: AppConstants.red,
                                              ),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppConstants.red,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppConstants.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'This room has expired',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppConstants.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Simple chat screen for confession rooms
class ConfessionRoomChatScreen extends StatefulWidget {
  final String roomId;
  final String roomName;

  const ConfessionRoomChatScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<ConfessionRoomChatScreen> createState() =>
      _ConfessionRoomChatScreenState();
}

class _ConfessionRoomChatScreenState extends State<ConfessionRoomChatScreen> {
  final ConfessionRoomsService _roomsService = ConfessionRoomsService();
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _roomsService.getRoomMessages(widget.roomId);
      if (mounted) {
        setState(() => _messages = messages);
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) return;

    try {
      await _roomsService.sendMessage(
        roomId: widget.roomId,
        message: _messageController.text,
      );
      _messageController.clear();
      _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        title: Text(
          widget.roomName,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: _loadMessages,
              icon: const Icon(
                Icons.refresh_rounded,
                color: AppConstants.primaryBlue,
              ),
              tooltip: 'Reload messages',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: AppConstants.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, idx) {
                      final msg = _messages[idx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppConstants.darkGray,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg['message'] as String? ?? '',
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${DateTime.parse(msg['created_at'] as String).hour}:${DateTime.parse(msg['created_at'] as String).minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppConstants.darkGray,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Anonymous message...',
                      hintStyle:
                          const TextStyle(color: AppConstants.textSecondary),
                      border: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: AppConstants.darkGray),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppConstants.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
