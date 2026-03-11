class ConfessionRoomModel {
  final String id;
  final String? creatorId;
  final String roomName;
  final String? description;
  final int maxParticipants;
  final String? joinCode;
  final DateTime expiresAt;
  final bool isActive;
  final DateTime createdAt;

  ConfessionRoomModel({
    required this.id,
    this.creatorId,
    required this.roomName,
    this.description,
    this.joinCode,
    this.maxParticipants = 50,
    required this.expiresAt,
    this.isActive = true,
    required this.createdAt,
  });

  factory ConfessionRoomModel.fromJson(Map<String, dynamic> json) {
    return ConfessionRoomModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String?,
      roomName: json['room_name'] as String,
      description: json['description'] as String?,
      joinCode: json['join_code'] as String?,
      maxParticipants: json['max_participants'] as int? ?? 50,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creator_id': creatorId,
      'room_name': roomName,
      'description': description,
      'join_code': joinCode,
      'max_participants': maxParticipants,
      'expires_at': expiresAt.toIso8601String(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeRemaining {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
}

class RoomMessageModel {
  final String id;
  final String roomId;
  final String? userId;
  final String message;
  final DateTime createdAt;

  RoomMessageModel({
    required this.id,
    required this.roomId,
    this.userId,
    required this.message,
    required this.createdAt,
  });

  factory RoomMessageModel.fromJson(Map<String, dynamic> json) {
    return RoomMessageModel(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String?,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'user_id': userId,
      'message': message,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
