import 'package:flutter/material.dart';
import '../../models/confession_room_model.dart';
import '../../services/confession_rooms_service.dart';
import '../../utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

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
  bool _canCreateRoom = false;

  @override
  void initState() {
    super.initState();
    _loadRooms();
    _loadCreatePermission();

    // If initialRoomId is provided, navigate to that room after loading
    if (widget.initialRoomId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToInitialRoom();
      });
    }
  }

  Future<void> _loadCreatePermission() async {
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('is_verified, role')
          .eq('id', widget.userId)
          .maybeSingle();
      final isVerified = res?['is_verified'] == true;
      final isAdmin = res?['role'] == 'admin';
      if (mounted) {
        setState(() => _canCreateRoom = isVerified || isAdmin);
      }
      await _loadRooms();
    } catch (e) {
      debugPrint('Error checking verification: $e');
    }
  }

  void _showNotVerifiedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Wait sorry not yet, focus on your streak 😎',
        ),
        backgroundColor: AppConstants.primaryBlue,
      ),
    );
  }

  void _copyJoinCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Join code copied'),
        backgroundColor: AppConstants.primaryBlue,
        duration: Duration(seconds: 2),
      ),
    );
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
      final rooms = _canCreateRoom
          ? await _roomsService.getUserRooms(widget.userId)
          : await _roomsService.getActiveRooms();
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
    if (!_canCreateRoom) {
      _showNotVerifiedMessage();
      return;
    }

    final nameController = TextEditingController();
    final rulesController = TextEditingController();
    final pinnedController = TextEditingController();
    int durationMinutes = 60;
    int startDelayMinutes = 0;

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
                  'Room rules (optional):',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rulesController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Add rules for this room...',
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
                  'Pinned message (optional):',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pinnedController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Message to pin at the top...',
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
                const SizedBox(height: 16),
                const Text(
                  'Start time:',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: startDelayMinutes,
                  onChanged: (v) {
                    setState(() => startDelayMinutes = v ?? 0);
                  },
                  isExpanded: true,
                  dropdownColor: AppConstants.darkGray,
                  items: [0, 15, 30, 60]
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            d == 0 ? 'Start now' : 'Start in $d minutes',
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
                      rules: rulesController.text.trim().isEmpty
                          ? null
                          : rulesController.text.trim(),
                      pinnedMessage: pinnedController.text.trim().isEmpty
                          ? null
                          : pinnedController.text.trim(),
                      scheduledStartAt: startDelayMinutes == 0
                          ? null
                          : DateTime.now()
                              .add(Duration(minutes: startDelayMinutes)),
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
                    final startsAt = room.scheduledStartAt;
                    final startsIn = startsAt != null
                        ? startsAt.difference(DateTime.now())
                        : Duration.zero;
                    final startsInMinutes = startsIn.inMinutes;
                    final hasStarted =
                        startsAt == null || startsAt.isBefore(DateTime.now());

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
                                          : !hasStarted
                                              ? 'Starts in ${startsInMinutes}m'
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
                            if ((room.joinCode ?? '').isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    'Join code: ',
                                    style: TextStyle(
                                      color: AppConstants.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    room.joinCode!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                      color: AppConstants.primaryBlue,
                                    ),
                                    onPressed: () =>
                                        _copyJoinCode(room.joinCode!),
                                    tooltip: 'Copy code',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (!room.isExpired)
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: hasStarted
                                          ? () {
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
                                            }
                                          : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppConstants.primaryBlue,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text(
                                        hasStarted
                                            ? 'Join Room'
                                            : 'Starts Soon',
                                      ),
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
  ConfessionRoomModel? _room;

  @override
  void initState() {
    super.initState();
    _loadRoomInfo();
    _loadMessages();
  }

  Future<void> _loadRoomInfo() async {
    try {
      final room = await _roomsService.getRoom(widget.roomId);
      if (mounted) {
        setState(() => _room = room);
      }
    } catch (e) {
      debugPrint('Error loading room info: $e');
    }
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
          if ((_room?.rules ?? '').isNotEmpty ||
              (_room?.pinnedMessage ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  if ((_room?.rules ?? '').isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppConstants.darkGray,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppConstants.primaryBlue.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Room Rules',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _room!.rules!,
                            style: const TextStyle(
                              color: AppConstants.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if ((_room?.pinnedMessage ?? '').isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppConstants.primaryBlue.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 18,
                            color: AppConstants.primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _room!.pinnedMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
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
