import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum RoomType { bedroom, kitchen, power, water, medical, storage, empty }

// İnşa edilebilen bir oda türünün maliyeti ve süresi.
class BuildOption {
  final RoomType type;
  final double electricityCost;

  // Tek bir inşaatçının tam verimle bitirme süresi (oyun saati).
  final double buildHours;

  const BuildOption(this.type, this.electricityCost, this.buildHours);
}

class ShelterRoom extends RectangleComponent {
  final String roomName;
  final RoomType type;
  final int floor;
  final int column;

  // Yatakhane: 4 yatak, revir: 2 sedye, diğer odalar: 3 kişi.
  // Boş alanda aynı anda en fazla 3 kişi inşaat yapar.
  late int capacity = switch (type) {
    RoomType.bedroom => 4,
    RoomType.medical => 2,
    _ => 3,
  };

  static const List<BuildOption> buildOptions = [
    BuildOption(RoomType.bedroom, 40, 4),
    BuildOption(RoomType.kitchen, 50, 4),
    BuildOption(RoomType.water, 50, 4),
    BuildOption(RoomType.power, 50, 4),
    BuildOption(RoomType.medical, 60, 6),
  ];

  static String nameOf(RoomType type) => switch (type) {
    RoomType.bedroom => 'Yatakhane',
    RoomType.kitchen => 'Yemekhane',
    RoomType.power => 'Elektrik',
    RoomType.water => 'Su Arıtma',
    RoomType.medical => 'Revir',
    RoomType.storage => 'Depo',
    RoomType.empty => 'Boş Alan',
  };

  static Color colorOf(RoomType type) => switch (type) {
    RoomType.bedroom => const Color(0xFF455A64),
    RoomType.kitchen => const Color(0xFF795548),
    RoomType.power => const Color(0xFF546E40),
    RoomType.water => const Color(0xFF346C84),
    RoomType.medical => const Color(0xFF607D8B),
    RoomType.storage => const Color(0xFF66564A),
    RoomType.empty => const Color(0xFF2A3036),
  };

  static String iconOf(RoomType type) => switch (type) {
    RoomType.bedroom => '🛏️',
    RoomType.kitchen => '🍲',
    RoomType.power => '⚡',
    RoomType.water => '💧',
    RoomType.medical => '🏥',
    RoomType.storage => '📦',
    RoomType.empty => '➕',
  };

  // İNŞAAT DURUMU (yalnızca boş alanlarda)
  BuildOption? construction;
  double constructionProgress = 0;

  bool get isUnderConstruction => construction != null;

  TextComponent? _iconText;

  ShelterRoom({
    required this.type,
    required this.floor,
    required this.column,
    required Vector2 position,
    required Vector2 size,
  }) : roomName = nameOf(type),
       super(
         position: position,
         size: size,
         paint: Paint()..color = colorOf(type),
         // Karakterler odaların önünde çizilsin.
         priority: -1,
       );

  Vector2 get standingPosition =>
      Vector2(position.x + size.x / 2, position.y + size.y - 10);

  void startConstruction(BuildOption option) {
    construction = option;
    constructionProgress = 0;
    _iconText?.text = '🚧';
  }

  void cancelConstruction() {
    construction = null;
    constructionProgress = 0;
    _iconText?.text = iconOf(type);
  }

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
          style: TextStyle(
            color: type == RoomType.empty ? Colors.white54 : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    _iconText = TextComponent(
      text: isUnderConstruction ? '🚧' : iconOf(type),
      position: Vector2(size.x / 2, size.y / 2 - 15),
      anchor: Anchor.center,
      textRenderer: TextPaint(style: const TextStyle(fontSize: 26)),
    );

    add(_iconText!);
  }

  static final TextPaint _constructionLabel = TextPaint(
    style: const TextStyle(color: Colors.amber, fontSize: 11),
  );

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final option = construction;
    if (option == null) return;

    // İnşaat ilerleme çubuğu
    final barRect = Rect.fromLTWH(8, size.y / 2 + 22, size.x - 16, 6);

    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(3)),
      Paint()..color = Colors.white12,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          barRect.left,
          barRect.top,
          barRect.width * constructionProgress.clamp(0.0, 1.0),
          barRect.height,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.amber,
    );

    _constructionLabel.render(
      canvas,
      '${nameOf(option.type)} %${(constructionProgress * 100).floor()}',
      Vector2(size.x / 2, barRect.top - 4),
      anchor: Anchor.bottomCenter,
    );
  }
}
