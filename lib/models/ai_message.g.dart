// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AiMessageAdapter extends TypeAdapter<AiMessage> {
  @override
  final int typeId = 10;

  @override
  AiMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AiMessage(
      text: fields[0] as String,
      isUser: fields[1] as bool,
      timestamp: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AiMessage obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.text)
      ..writeByte(1)
      ..write(obj.isUser)
      ..writeByte(2)
      ..write(obj.timestamp);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
