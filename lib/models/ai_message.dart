import 'package:hive/hive.dart';

part 'ai_message.g.dart';

@HiveType(typeId: 10) // Unique ID for Hive
class AiMessage extends HiveObject {
  @HiveField(0)
  final String text;

  @HiveField(1)
  final bool isUser; // true if sent by user, false if from AI

  @HiveField(2)
  final DateTime timestamp;

  AiMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
