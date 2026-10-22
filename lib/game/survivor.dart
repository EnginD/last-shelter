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

  goingToMedical,
  healing,
}

enum SurvivorRoomAction { work, eat, drink, rest, idle }

class Survivor extends PositionComponent {
  final String name;
  final double speed = 90;

  final Queue<Vector2> _path = Queue<Vector2>();

  SurvivorRoomAction roomAction = SurvivorRoomAction.idle;
  SurvivorState state = SurvivorState.idle;

  bool manualNeedAction = false;

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

  // Otomatik tedavi sistemi
  bool autoHealing = false;
  int? medicalRoomIndex;

  bool manualResting = false;

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
  bool returnToManualRest = false;
  int? manualRestRoomIndex;
  double needActionDuration = 0;
  double needActionStartValue = 0;

  bool foodReserved = false;
  bool waterReserved = false;

  // Rezerve edilen yemek/su miktarı (iade için).
  double reservedAmount = 0;

  // Yeme/içme bittiğinde ulaşılacak değer. Stok yetmediyse 100'den azdır.
  double needActionTarget = 100;

  // Zorluk seviyesine göre açlık/susuzluk hasarı çarpanı.
  double starvationDamageMultiplier = 1.0;
  bool isDead = false;

  // Dakikada azalan ihtiyaç miktarları
  //static const double hungerLossPerMinute = 36.0; // 12 → 36
  //static const double thirstLossPerMinute = 45.0; // 15 → 45
  //static const double healthLossPerMinute = 5.0; // Değişmedi

  static const double hungerLossPerMinute = 12.0;
  static const double thirstLossPerMinute = 15.0;
  static const double healthLossPerMinute = 5.0;

  static const double energyConsumption = 10.0;
  static const double energyRecovery = 20.0;

  //static const double energyConsumption = 2.0 / 60;
  //static const double energyRecovery = 8.0 / 60;

  void checkDeath() {
    if (isDead || health > 0) return;

    health = 0;
    isDead = true;

    isWorking = false;
    isResting = false;
    autoEating = false;
    autoDrinking = false;
    autoResting = false;
    autoHealing = false;
    medicalRoomIndex = null;

    state = SurvivorState.idle;
  }

  double get needActionProgress {
    if (needActionDuration <= 0) return 0;

    return (needActionTimer / needActionDuration).clamp(0.0, 1.0).toDouble();
  }

  void assignToRoom(int roomIndex) {
    assignedRoomIndex = roomIndex;
    isWorking = false;
  }

  void updateNeeds(double dt) {
    final isEating = !isMoving && state == SurvivorState.eating;
    final isDrinking = !isMoving && state == SurvivorState.drinking;

    if (!isEating) {
      hunger -= hungerLossPerMinute * dt / 60;
    }

    if (!isDrinking) {
      thirst -= thirstLossPerMinute * dt / 60;
    }

    hunger = hunger.clamp(0.0, 100.0);
    thirst = thirst.clamp(0.0, 100.0);

    // SAĞLIK SİSTEMİ
    double healthLoss = 0;

    if (hunger <= 0) healthLoss += 12.0 * starvationDamageMultiplier;
    if (thirst <= 0) healthLoss += 18.0 * starvationDamageMultiplier;

    if (healthLoss > 0) {
      health -= healthLoss * dt / 60;
    } else if (!autoHealing && hunger >= 50 && thirst >= 50 && energy >= 25) {
      health += 3.0 * dt / 60;
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
    const double walkingEnergyLossPerMinute = 12.0;
    const double workingEnergyLossPerMinute = 15.0;
    const double restingEnergyGainPerMinute = 25.0;

    if (isMoving) {
      energy -= walkingEnergyLossPerMinute * dt / 60;
    } else if (state == SurvivorState.sleeping) {
      energy += restingEnergyGainPerMinute * dt / 60;
    } else if (isWorking) {
      energy -= workingEnergyLossPerMinute * dt / 60;
    }

    energy = energy.clamp(0.0, 100.0);
  }
}
