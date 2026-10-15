import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum RoomType { bedroom, kitchen, power, water, medical, storage }

class ShelterRoom extends RectangleComponent {
  final String roomName;
  final RoomType type;
  final int floor;
  final int roomIndex;

  int capacity = 3;

  ShelterRoom({
    required this.roomName,
    required this.type,
    required this.floor,
    required this.roomIndex,
    required Vector2 position,
    required Vector2 size,
    required Color color,
  }) : super(position: position, size: size, paint: Paint()..color = color);

  Vector2 get standingPosition =>
      Vector2(position.x + size.x / 2, position.y + size.y - 10);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    add(
      RectangleComponent(
        position: Vector2(0, size.y - 7),
        size: Vector2(size.x, 7),
        paint: Paint()..color = const Color(0xFF29343B),
      ),
    );

    add(
      TextComponent(
        text: roomName,
        position: Vector2(8, 10),
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    add(
      TextComponent(
        text: _roomIcon(),
        position: Vector2(size.x / 2, size.y / 2 - 15),
        anchor: Anchor.center,
        textRenderer: TextPaint(style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  String _roomIcon() {
    switch (type) {
      case RoomType.bedroom:
        return '🛏️';
      case RoomType.kitchen:
        return '🍲';
      case RoomType.power:
        return '⚡';
      case RoomType.water:
        return '💧';
      case RoomType.medical:
        return '🏥';
      case RoomType.storage:
        return '📦';
    }
  }
}
