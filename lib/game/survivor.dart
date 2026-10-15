import 'dart:collection';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum SurvivorState {
  idle,
  walking,
  working,
  sleeping,
  waitingForBed,
  goingToEat,
  eating,
  goingToDrink,
  drinking,
  waitingForFood,
  waitingForWater,
}

class Survivor extends PositionComponent {
  final String name;
  final double speed = 90;

  final Queue<Vector2> _path = Queue<Vector2>();

  SurvivorState state = SurvivorState.idle;

  int age = 25;

  int electricitySkill = 50;
  int waterSkill = 50;
  int cookingSkill = 50;

  // Karakterin asıl görevli olduğu oda
  int? workRoomIndex;

  // Geçici dinlenme için kullanılan yatak
  int? restRoomIndex;

  // Otomatik dinlenme sürecinde mi?
  bool autoResting = false;

  // Hedef odaya gerçekten ulaştı mı?
  int? currentRoomIndex;

  bool isSelected = false;
  int currentFloor;

  bool isWorking = false;
  int? assignedRoomIndex;

  double health = 100;
  double hunger = 100;
  double thirst = 100;

  double energy = 100;

  bool isResting = false;

  bool autoEating = false;
  bool autoDrinking = false;

  int? needRoomIndex;
  int? destinationFloor;
  double needActionTimer = 0;

  // Dakikada azalan ihtiyaç miktarları
  static const double hungerLossPerMinute = 12.0;
  static const double thirstLossPerMinute = 15.0;
  static const double healthLossPerMinute = 5.0;

  static const double energyConsumption = 10.0;
  static const double energyRecovery = 20.0;

  //static const double energyConsumption = 2.0 / 60;
  //static const double energyRecovery = 8.0 / 60;

  void assignToRoom(int roomIndex) {
    assignedRoomIndex = roomIndex;
    isWorking = false;
  }

  void updateNeeds(double dt) {
    hunger -= hungerLossPerMinute * dt / 60;
    thirst -= thirstLossPerMinute * dt / 60;

    hunger = hunger.clamp(0.0, 100.0);
    thirst = thirst.clamp(0.0, 100.0);

    if (hunger <= 10 || thirst <= 10) {
      health -= healthLossPerMinute * dt / 60;
    }

    health = health.clamp(0.0, 100.0);
  }

  Survivor({
    required this.name,
    required this.currentFloor,
    required Vector2 position,
  }) : super(
         position: position,
         size: Vector2(24, 48),
         anchor: Anchor.bottomCenter,
       );

  bool get isMoving => _path.isNotEmpty;
  bool get hasArrived => !isMoving;

  void moveAlong(List<Vector2> points, int targetFloor) {
    _path.clear();

    for (final point in points) {
      _path.add(point.clone());
    }

    destinationFloor = targetFloor;

    isWorking = false;
    isResting = false;

    if (_path.isNotEmpty) {
      state = SurvivorState.walking;
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Seçim göstergesi
    add(
      CircleComponent(
        radius: 18,
        position: Vector2(12, 23),
        anchor: Anchor.center,
        paint: Paint()..color = Colors.yellow.withValues(alpha: 0.20),
      )..priority = -1,
    );

    add(
      RectangleComponent(
        position: Vector2(4, 17),
        size: Vector2(16, 28),
        paint: Paint()..color = Colors.blueGrey.shade200,
      ),
    );

    add(
      CircleComponent(
        position: Vector2(4, 0),
        radius: 8,
        paint: Paint()..color = Colors.orange.shade200,
      ),
    );

    add(
      TextComponent(
        text: name,
        position: Vector2(12, -18),
        anchor: Anchor.center,
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    if (isSelected) {
      final selectionPaint = Paint()
        ..color = Colors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(const Offset(12, 24), 20, selectionPaint);
    }

    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);

    var remainingDistance = speed * dt;

    while (_path.isNotEmpty && remainingDistance > 0) {
      final destination = _path.first;
      final direction = destination - position;
      final distance = direction.length;

      if (distance <= remainingDistance) {
        position.setFrom(destination);
        _path.removeFirst();
        remainingDistance -= distance;
      } else {
        direction.normalize();
        position.add(direction * remainingDistance);
        remainingDistance = 0;
      }
    }

    // Karakter hedef kata ulaştığında kat bilgisini güncelle.
    if (!isMoving && destinationFloor != null) {
      currentFloor = destinationFloor!;
      destinationFloor = null;
    }
  }

  void updateEnergy(double dt) {
    if (isMoving) return;

    if (autoResting) {
      if (state == SurvivorState.sleeping) {
        energy = (energy + energyRecovery * dt).clamp(0.0, 100.0);
      }
      return;
    }

    if (isWorking) {
      energy = (energy - energyConsumption * dt).clamp(0.0, 100.0);
    } else {
      energy = (energy + energyRecovery * dt).clamp(0.0, 100.0);
    }
  }
}
