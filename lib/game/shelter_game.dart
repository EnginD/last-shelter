import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'resource_manager.dart';
import 'dart:collection';
import '../models/survivor_candidate.dart';

import 'room.dart';
import 'survivor.dart';

class SurvivorNotifier extends ValueNotifier<Survivor?> {
  SurvivorNotifier() : super(null);

  void refresh() {
    notifyListeners();
  }
}

class ShelterGame extends FlameGame with TapCallbacks {
  final List<Survivor> survivors = [];
  final List<ShelterRoom> rooms = [];
  final Map<Survivor, int> occupantSlot = {};
  final SurvivorNotifier selectedCharacter = SurvivorNotifier();
  final ValueNotifier<int> uiRefresh = ValueNotifier<int>(0);

  int selectedSurvivor = 0;
  int nextSurvivorId = 4;

  static const double roomHeight = 145;
  static const double roomGap = 8;
  static const double floorGap = 42;
  static const double sideMargin = 10;

  double roomWidth = 0;
  double top = 0;
  double stairX = 0;

  final ValueNotifier<String?> deathNotification = ValueNotifier<String?>(null);

  final Queue<String> _deathNotificationQueue = Queue<String>();

  double deathNotificationTimer = 0;

  final ValueNotifier<bool> isGameOver = ValueNotifier<bool>(false);

  void _checkGameOver() {
    if (isGameOver.value || survivors.isNotEmpty) return;

    isGameOver.value = true;

    debugPrint('GAME OVER: Sığınaktaki herkes hayatını kaybetti.');
  }

  void _showDeathNotification(String survivorName) {
    final message = '☠️ $survivorName hayatını kaybetti!';

    _deathNotificationQueue.add(message);

    _showNextDeathNotification();
  }

  void _showNextDeathNotification() {
    // Ekranda zaten bildirim varsa bekle.
    if (deathNotification.value != null) return;

    if (_deathNotificationQueue.isEmpty) return;

    deathNotification.value = _deathNotificationQueue.removeFirst();
    deathNotificationTimer = 5.0;
  }

  void _clearNeedReservations(Survivor survivor) {
    if (survivor.foodReserved) {
      resourceManager.food += 1;
      survivor.foodReserved = false;
    }

    if (survivor.waterReserved) {
      resourceManager.water += 1;
      survivor.waterReserved = false;
    }
  }

  void setTestResources({double? food, double? water}) {
    if (food != null) {
      resourceManager.food = food;
    }

    if (water != null) {
      resourceManager.water = water;
    }
  }

  double _skillMultiplier(int skill) {
    return 0.5 + skill.clamp(0, 100) / 100.0;
  }

  double _needMultiplier(double value) {
    if (value >= 75) return 1.0;
    if (value >= 50) return 0.90;
    if (value >= 25) return 0.75;
    return 0.50;
  }

  double _survivorEfficiency(Survivor survivor) {
    final health = _needMultiplier(survivor.health);
    final energy = _needMultiplier(survivor.energy);
    final hunger = _needMultiplier(survivor.hunger);
    final thirst = _needMultiplier(survivor.thirst);

    return (health + energy + hunger + thirst) / 4.0;
  }

  final ResourceManager resourceManager = ResourceManager();
  final Map<Survivor, int> destinationRooms = {};

  double resourceUiTimer = 0;
  TextComponent? resourceText;

  void Function(Survivor survivor, int roomIndex)? onRoomActionRequested;

  @override
  Color backgroundColor() => const Color(0xFF171B20);

  double _calculateNeedDuration({
    required double currentValue,
    required bool isWater,
  }) {
    final value = currentValue.clamp(0.0, 100.0);

    final minDuration = isWater ? 3.0 : 4.0;
    final maxDuration = isWater ? 12.0 : 20.0;

    return minDuration + (100.0 - value) / 100.0 * (maxDuration - minDuration);
  }

  void assignSurvivorToRoom(
    Survivor survivor,
    int roomIndex,
    SurvivorRoomAction action,
  ) {
    final room = rooms[roomIndex];

    // İşlem ile oda türünün uyumunu kontrol et.
    if (action == SurvivorRoomAction.eat && room.type != RoomType.kitchen) {
      return;
    }

    if (action == SurvivorRoomAction.drink && room.type != RoomType.water) {
      return;
    }

    if (action == SurvivorRoomAction.rest && room.type != RoomType.bedroom) {
      return;
    }

    // Önce oda atamasını yap.
    final alreadyInRoom =
        !survivor.isMoving && survivor.currentRoomIndex == roomIndex;

    if (!alreadyInRoom) {
      final success = _sendSurvivorToRoom(survivor, roomIndex);
      if (!success) return;
    }

    // Önceki yemek/su rezervasyonunu temizle.
    _clearNeedReservations(survivor);

    // Önceki manuel/otomatik işlemleri temizle.
    survivor.autoEating = false;
    survivor.autoDrinking = false;
    survivor.autoResting = false;
    survivor.manualResting = false;

    survivor.returnToManualRest = false;
    survivor.manualRestRoomIndex = null;

    survivor.needRoomIndex = null;
    survivor.restRoomIndex = null;
    survivor.needActionTimer = 0;
    survivor.needActionDuration = 0;

    survivor.roomAction = action;

    // Manuel yemek veya su işlemi.
    survivor.manualNeedAction =
        action == SurvivorRoomAction.eat || action == SurvivorRoomAction.drink;

    if (survivor.manualNeedAction) {
      final isWater = action == SurvivorRoomAction.drink;

      survivor.autoEating = !isWater;
      survivor.autoDrinking = isWater;
      survivor.needRoomIndex = roomIndex;

      // Önce mevcut ihtiyaç seviyesini kaydet.
      survivor.needActionStartValue = isWater
          ? survivor.thirst
          : survivor.hunger;

      survivor.needActionTimer = 0;
      survivor.needActionDuration = 0;
      survivor.isWorking = false;
      return;
    }

    if (action == SurvivorRoomAction.rest) {
      survivor.manualResting = true;
      survivor.isWorking = false;
      return;
    }

    if (action == SurvivorRoomAction.work) {
      survivor.workRoomIndex = roomIndex;

      survivor.autoDrinking = false;
      survivor.autoEating = false;
      survivor.manualNeedAction = false;

      survivor.isWorking = !survivor.isMoving;

      if (!survivor.isMoving) {
        survivor.state = SurvivorState.working;
      }

      return;
    }

    survivor.workRoomIndex = null;
    survivor.isWorking = false;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    debugPrint('ShelterGame onLoad started');
    debugPrint('Game size: ${size.x} x ${size.y}');

    roomWidth = (size.x - 4 * sideMargin) / 3;
    top = 95;
    stairX = size.x - sideMargin / 2;

    _createRooms();
    _createStairs();
    _createSurvivors();
    _createResourceBar();

    debugPrint('Rooms created: ${rooms.length}');
    debugPrint('Survivors created: ${survivors.length}');
  }

  double floorY(int floor) {
    return top + floor * (roomHeight + floorGap);
  }

  void _createRooms() {
    final definitions = [
      ('Yatakhane', RoomType.bedroom, const Color(0xFF455A64)),
      ('Yemekhane', RoomType.kitchen, const Color(0xFF795548)),
      ('Elektrik', RoomType.power, const Color(0xFF546E40)),
      ('Su Arıtma', RoomType.water, const Color(0xFF346C84)),
      ('Revir', RoomType.medical, const Color(0xFF607D8B)),
      ('Depo', RoomType.storage, const Color(0xFF66564A)),
    ];

    for (int i = 0; i < definitions.length; i++) {
      final floor = i ~/ 3;
      final column = i % 3;

      final room = ShelterRoom(
        roomName: definitions[i].$1,
        type: definitions[i].$2,
        floor: floor,
        roomIndex: column,
        position: Vector2(
          sideMargin + column * (roomWidth + sideMargin),
          floorY(floor),
        ),
        size: Vector2(roomWidth, roomHeight),
        color: definitions[i].$3,
      );

      rooms.add(room);
      add(room);
    }
  }

  void _createStairs() {
    final upperFloor = floorY(0) + roomHeight - 10;
    final lowerFloor = floorY(1) + roomHeight - 10;

    // Merdiven şaftı
    add(
      RectangleComponent(
        position: Vector2(stairX - 4, upperFloor),
        size: Vector2(8, lowerFloor - upperFloor),
        paint: Paint()..color = Colors.grey.shade600,
      ),
    );

    // Merdiven basamakları
    for (double y = upperFloor; y < lowerFloor; y += 14) {
      add(
        RectangleComponent(
          position: Vector2(stairX - 9, y),
          size: Vector2(18, 3),
          paint: Paint()..color = Colors.grey.shade300,
        ),
      );
    }
  }

  void _createSurvivors() {
    final names = ['Ahmet', 'Ayşe', 'Mehmet'];

    for (int i = 0; i < names.length; i++) {
      final room = rooms[i];

      final survivor = Survivor(
        name: names[i],
        currentFloor: room.floor,
        position: _slotPosition(room, 0),
      );

      // Başlangıçtaki karakterin oda bilgisi
      survivor.assignedRoomIndex = i;
      survivor.currentRoomIndex = i;

      if (room.type == RoomType.power ||
          room.type == RoomType.water ||
          room.type == RoomType.kitchen) {
        survivor.workRoomIndex = i;
      }

      // Başlangıç karakterine slot 0 ver
      occupantSlot[survivor] = 0;

      survivor.isSelected = i == selectedSurvivor;

      survivors.add(survivor);
      add(survivor);
    }
  }

  void _createResourceBar() {
    resourceText = TextComponent(
      text: '',
      position: Vector2(12, 12),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    add(resourceText!);
    _refreshResourceText();
  }

  void _refreshResourceText() {
    resourceText?.text =
        '⚡ ${resourceManager.electricity.floor()} '
        '${_resourceTrend(resourceManager.electricityNetPerMinute)}\n'
        '💧 ${resourceManager.water.floor()} '
        '${_resourceTrend(resourceManager.waterNetPerMinute)}\n'
        '🍞 ${resourceManager.food.floor()} '
        '${_resourceTrend(resourceManager.foodNetPerMinute)}\n'
        '👥 ${survivors.length}/${resourceManager.maxPopulation}';
  }

  List<Vector2> _buildPath(Survivor survivor, ShelterRoom targetRoom) {
    final destination = targetRoom.standingPosition;
    final current = survivor.position.clone();

    // Her katın merdiven çıkış konumunu belirle.
    Vector2 stairPosition(int floor) {
      final room = rooms.firstWhere((r) => r.floor == floor);

      return Vector2(stairX, room.position.y + room.size.y - 10);
    }

    final targetStair = stairPosition(targetRoom.floor);

    // Karakterin mevcut konumuna en yakın katı bul.
    final floors = rooms.map((r) => r.floor).toSet().toList();

    int nearestFloor = floors.first;
    double nearestDistance = double.infinity;

    for (final floor in floors) {
      final stair = stairPosition(floor);
      final distance = (current.y - stair.y).abs();

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestFloor = floor;
      }
    }

    final currentStair = stairPosition(nearestFloor);

    // Merdivenin üzerinde mi?
    const stairTolerance = 8.0;

    final isOnStairs = (current.x - stairX).abs() <= stairTolerance;

    // Merdivendeyse hedef katın çıkışına git.
    if (isOnStairs) {
      return [targetStair, destination];
    }

    // Zaten hedef kattaysa doğrudan ilerle.
    if (nearestFloor == targetRoom.floor) {
      return [destination];
    }

    // Başka kattaysa merdiven üzerinden git.
    return [currentStair, targetStair, destination];
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);

    final tap = event.localPosition;

    // Karakter seçimi
    for (int i = survivors.length - 1; i >= 0; i--) {
      final survivor = survivors[i];

      final characterRect = Rect.fromLTWH(
        survivor.position.x - 12,
        survivor.position.y - 48,
        24,
        48,
      ).inflate(4);

      if (characterRect.contains(tap.toOffset())) {
        selectedSurvivor = i;
        selectedCharacter.value = survivor;

        for (int j = 0; j < survivors.length; j++) {
          survivors[j].isSelected = j == i;
        }

        return;
      }
    }

    // Oda seçimi
    for (int i = 0; i < rooms.length; i++) {
      final room = rooms[i];

      if (!room.toRect().contains(tap.toOffset())) {
        continue;
      }

      if (selectedSurvivor < 0 || selectedSurvivor >= survivors.length) {
        return;
      }

      final survivor = survivors[selectedSurvivor];

      // Yemekhane ve su odasında işlem seçimi göster.
      if (room.type == RoomType.kitchen || room.type == RoomType.water) {
        onRoomActionRequested?.call(survivor, i);
        return;
      }

      // Yatakhane ve diğer odalarda mevcut görevlendirme.
      final action = room.type == RoomType.bedroom
          ? SurvivorRoomAction.rest
          : room.type == RoomType.power
          ? SurvivorRoomAction.work
          : SurvivorRoomAction.idle;

      assignSurvivorToRoom(survivor, i, action);
      return;
    }
  }

  @override
  void update(double dt) {
    if (isGameOver.value) return;

    super.update(dt);

    double electricityProduction = 0;
    double waterProduction = 0;
    double foodProduction = 0;

    uiRefresh.value++;

    for (final survivor in survivors) {
      _updateAutomaticBehavior(survivor);
      _updateAutomaticNeeds(survivor, dt);

      survivor.updateEnergy(dt);
      survivor.updateNeeds(dt);
      survivor.checkDeath();

      // Ölen karakter üretim yapamaz.
      if (survivor.isDead) continue;

      if (survivor.isMoving ||
          survivor.autoResting ||
          survivor.autoEating ||
          survivor.autoDrinking ||
          !survivor.isWorking ||
          survivor.assignedRoomIndex == null) {
        continue;
      }

      final room = rooms[survivor.assignedRoomIndex!];
      final efficiency = _survivorEfficiency(survivor);

      switch (room.type) {
        case RoomType.power:
          electricityProduction +=
              6.0 * _skillMultiplier(survivor.electricitySkill) * efficiency;
          break;

        case RoomType.water:
          waterProduction +=
              5.0 * _skillMultiplier(survivor.waterSkill) * efficiency;
          break;

        case RoomType.kitchen:
          foodProduction +=
              4.0 * _skillMultiplier(survivor.cookingSkill) * efficiency;
          break;

        default:
          break;
      }
    }

    resourceManager.updateProduction(
      electricity: electricityProduction,
      water: waterProduction,
      food: foodProduction,
    );

    resourceManager.updateResources(dt);

    resourceUiTimer += dt;

    _removeDeadSurvivors();

    // Son karakter öldüyse Game Over.
    _checkGameOver();

    if (deathNotificationTimer > 0) {
      deathNotificationTimer -= dt;

      if (deathNotificationTimer <= 0) {
        deathNotificationTimer = 0;
        deathNotification.value = null;
        _showNextDeathNotification();
      }
    }

    if (resourceUiTimer >= 0.5) {
      resourceUiTimer = 0;
      _refreshResourceText();

      if (selectedCharacter.value != null) {
        selectedCharacter.refresh();
      }
    }
  }

  Vector2 _slotPosition(ShelterRoom room, int slot) {
    const spacing = 28.0;

    final centerX = room.position.x + room.size.x / 2;

    return Vector2(
      centerX + (slot - (room.capacity - 1) / 2) * spacing,
      room.position.y + room.size.y - 10,
    );
  }

  Vector2 _getRoomPosition(ShelterRoom room, Survivor survivor) {
    final roomIndex = rooms.indexOf(room);

    final occupants = survivors
        .where((s) => s != survivor && s.assignedRoomIndex == roomIndex)
        .toList();

    final usedSlots = <int>{};

    for (final occupant in occupants) {
      final slot = occupantSlot[occupant];

      if (slot != null) {
        usedSlots.add(slot);
      }
    }

    for (int slot = 0; slot < room.capacity; slot++) {
      if (!usedSlots.contains(slot)) {
        occupantSlot[survivor] = slot;
        return _slotPosition(room, slot);
      }
    }

    return room.standingPosition;
  }

  int? _findAvailableBedroom(Survivor survivor) {
    for (int i = 0; i < rooms.length; i++) {
      final room = rooms[i];

      if (room.type != RoomType.bedroom) continue;

      final occupied = survivors
          .where((s) => s != survivor && s.assignedRoomIndex == i)
          .length;

      if (occupied < room.capacity) {
        return i;
      }
    }

    return null;
  }

  bool _sendSurvivorToRoom(Survivor survivor, int roomIndex) {
    final room = rooms[roomIndex];

    final occupants = survivors
        .where((s) => s != survivor && s.assignedRoomIndex == roomIndex)
        .length;

    if (occupants >= room.capacity) {
      return false;
    }

    // Eski oda rezervasyonunu bırak.
    occupantSlot.remove(survivor);

    // Yeni odayı rezerve et.
    survivor.assignToRoom(roomIndex);

    final destination = _getRoomPosition(room, survivor);
    final path = _buildPath(survivor, room);

    if (path.isNotEmpty) {
      path[path.length - 1] = destination;
    }

    destinationRooms[survivor] = roomIndex;

    survivor.moveAlong(path, room.floor);

    return true;
  }

  void _startAutomaticRest(Survivor survivor) {
    final bedroomIndex = _findAvailableBedroom(survivor);

    if (bedroomIndex == null) {
      survivor.state = SurvivorState.waitingForBed;
      survivor.isWorking = false;
      return;
    }

    survivor.workRoomIndex ??= survivor.assignedRoomIndex;

    survivor.autoResting = true;
    survivor.restRoomIndex = bedroomIndex;

    final success = _sendSurvivorToRoom(survivor, bedroomIndex);

    if (!success) {
      survivor.autoResting = false;
      survivor.state = SurvivorState.waitingForBed;
    }
  }

  void _finishAutomaticRest(Survivor survivor) {
    final workRoom = survivor.workRoomIndex;

    if (workRoom == null) {
      survivor.autoResting = false;
      survivor.state = SurvivorState.idle;
      return;
    }

    final success = _sendSurvivorToRoom(survivor, workRoom);

    if (success) {
      survivor.autoResting = false;
      survivor.restRoomIndex = null;
    }
  }

  void _updateAutomaticBehavior(Survivor survivor) {
    if (survivor.isMoving) return;

    // Önce karakterin vardığı odayı ve katı güncelle.
    final destination = destinationRooms.remove(survivor);

    if (destination != null) {
      survivor.currentRoomIndex = destination;
      survivor.currentFloor = rooms[destination].floor;
    }

    // Ardından otomatik yemek/su durumunu kontrol et.
    if (survivor.autoEating || survivor.autoDrinking) {
      survivor.isWorking = false;
      return;
    }

    // Manuel dinlenme
    if (survivor.manualResting) {
      final roomIndex = survivor.currentRoomIndex;

      if (roomIndex != null && rooms[roomIndex].type == RoomType.bedroom) {
        survivor.isWorking = false;

        if (survivor.energy < 100) {
          survivor.state = SurvivorState.sleeping;
        } else {
          survivor.state = SurvivorState.idle;
        }

        return;
      }
    }

    // Otomatik dinlenme süreci
    if (survivor.autoResting) {
      if (survivor.restRoomIndex != null &&
          survivor.currentRoomIndex == survivor.restRoomIndex) {
        survivor.state = SurvivorState.sleeping;
        survivor.isWorking = false;

        if (survivor.energy >= 100) {
          _finishAutomaticRest(survivor);
        }
      }

      return;
    }

    // Yorgunluk kontrolü
    if (survivor.energy <= 20 && survivor.workRoomIndex != null) {
      final canDrink = survivor.thirst <= 25 && resourceManager.water >= 1;

      final canEat = survivor.hunger <= 25 && resourceManager.food >= 1;

      // Karakterin karşılanabilecek kritik ihtiyacı varsa
      // önce _updateAutomaticNeeds() ilgilensin.
      if (!canDrink && !canEat) {
        _startAutomaticRest(survivor);
        return;
      }
    }

    // Normal çalışma
    if (survivor.assignedRoomIndex != null) {
      final room = rooms[survivor.assignedRoomIndex!];

      if (room.type == RoomType.power ||
          room.type == RoomType.water ||
          room.type == RoomType.kitchen) {
        survivor.state = SurvivorState.working;
        survivor.isWorking = true;
      } else {
        survivor.state = SurvivorState.idle;
        survivor.isWorking = false;
      }
    }
  }

  String _resourceTrend(double value) {
    if (value > 0.001) {
      return '↑ +${value.toStringAsFixed(1)}/dk';
    }

    if (value < -0.001) {
      return '↓ ${value.toStringAsFixed(1)}/dk';
    }

    return '→ 0.0/dk';
  }

  bool addNewSurvivor(SurvivorCandidate candidate) {
    if (survivors.length >= resourceManager.maxPopulation) {
      return false;
    }

    final bedroomIndex = rooms.indexWhere(
      (room) => room.type == RoomType.bedroom,
    );

    if (bedroomIndex == -1) return false;

    final room = rooms[bedroomIndex];

    final occupied = survivors
        .where((s) => s.assignedRoomIndex == bedroomIndex)
        .length;

    if (occupied >= room.capacity) {
      return false;
    }

    final survivor = Survivor(
      name: candidate.name,
      currentFloor: room.floor,
      position: Vector2.zero(),
    );

    survivor.health = candidate.health.toDouble();

    survivor.electricitySkill = candidate.electricitySkill;
    survivor.waterSkill = candidate.waterSkill;
    survivor.cookingSkill = candidate.cookingSkill;
    survivor.age = candidate.age;

    survivor.assignedRoomIndex = bedroomIndex;
    survivor.currentRoomIndex = bedroomIndex;

    survivor.position = _getRoomPosition(room, survivor);

    survivors.add(survivor);
    add(survivor);

    resourceManager.population = survivors.length;

    _refreshResourceText();

    return true;
  }

  int? _findAvailableNeedRoom(Survivor survivor, RoomType type) {
    for (int i = 0; i < rooms.length; i++) {
      final room = rooms[i];

      if (room.type != type) continue;

      final occupied = survivors
          .where((s) => s != survivor && s.assignedRoomIndex == i)
          .length;

      if (occupied < room.capacity) {
        return i;
      }
    }

    return null;
  }

  void _startAutomaticNeed(Survivor survivor, {required bool isWater}) {
    if (survivor.isMoving || survivor.autoEating || survivor.autoDrinking) {
      return;
    }

    final roomType = isWater ? RoomType.water : RoomType.kitchen;

    final roomIndex = _findAvailableNeedRoom(survivor, roomType);

    if (roomIndex == null) return;

    // Kaynağı karakter yola çıkmadan önce ayır.
    final consumed = isWater
        ? resourceManager.consumeWater(1)
        : resourceManager.consumeFood(1);

    if (!consumed) return;

    final previousWorkRoom = survivor.workRoomIndex;
    final previousAssignedRoom = survivor.assignedRoomIndex;

    survivor.workRoomIndex ??= survivor.assignedRoomIndex;

    final alreadyInRoom = survivor.currentRoomIndex == roomIndex;

    if (!alreadyInRoom) {
      final success = _sendSurvivorToRoom(survivor, roomIndex);

      if (!success) {
        // Hareket başlatılamadıysa kaynağı iade et.
        if (isWater) {
          resourceManager.water += 1;
        } else {
          resourceManager.food += 1;
        }

        survivor.workRoomIndex = previousWorkRoom;
        survivor.assignedRoomIndex = previousAssignedRoom;
        return;
      }
    }

    survivor.autoEating = !isWater;
    survivor.autoDrinking = isWater;

    survivor.foodReserved = !isWater;
    survivor.waterReserved = isWater;

    survivor.needRoomIndex = roomIndex;
    survivor.needActionTimer = 0;
    survivor.needActionDuration = 0;

    survivor.needActionStartValue = isWater ? survivor.thirst : survivor.hunger;

    survivor.isWorking = false;

    survivor.state = alreadyInRoom
        ? (isWater ? SurvivorState.drinking : SurvivorState.eating)
        : (isWater ? SurvivorState.goingToDrink : SurvivorState.goingToEat);

    /*
    debugPrint(
      'NEED RESERVED: ${survivor.name} '
      'type=$roomType '
      'food=${resourceManager.food.toStringAsFixed(2)} '
      'water=${resourceManager.water.toStringAsFixed(2)}',
    );
    */
  }

  void _finishAutomaticNeed(Survivor survivor) {
    if (survivor.manualNeedAction) {
      survivor.foodReserved = false;
      survivor.waterReserved = false;

      survivor.manualNeedAction = false;
      survivor.needActionStartValue = 0;

      survivor.needActionTimer = 0;
      survivor.needActionDuration = 0;
      survivor.needActionStartValue = 0;

      survivor.autoEating = false;
      survivor.autoDrinking = false;
      survivor.needRoomIndex = null;

      survivor.needActionTimer = 0;
      survivor.needActionDuration = 0;

      survivor.roomAction = SurvivorRoomAction.idle;
      survivor.workRoomIndex = null;

      survivor.isWorking = false;
      survivor.state = SurvivorState.idle;
      return;
    }

    // Otomatik yemek / su işlemini tamamla.
    survivor.autoEating = false;
    survivor.autoDrinking = false;
    survivor.needRoomIndex = null;
    survivor.needActionTimer = 0;

    // Manuel dinlenme sırasında ihtiyaç için ayrıldıysa
    // tekrar yatakhaneye dön.
    if (survivor.returnToManualRest) {
      final bedroomIndex = survivor.manualRestRoomIndex;

      survivor.returnToManualRest = false;
      survivor.manualRestRoomIndex = null;

      if (bedroomIndex != null) {
        // Zaten yatakhanedeyse hareket ettirme.
        if (!survivor.isMoving && survivor.currentRoomIndex == bedroomIndex) {
          survivor.manualResting = true;
          survivor.isWorking = false;
          survivor.state = survivor.energy < 100
              ? SurvivorState.sleeping
              : SurvivorState.idle;
          return;
        }

        // Yatakhaneye geri gönder.
        final success = _sendSurvivorToRoom(survivor, bedroomIndex);

        if (success) {
          survivor.manualResting = true;
          survivor.isWorking = false;
          return;
        }
      }

      // Yatakhaneye dönemiyorsa bekle.
      survivor.manualResting = false;
      survivor.isWorking = false;
      survivor.state = SurvivorState.idle;
      return;
    }

    // Normal çalışma odasına geri dön.
    final workRoom = survivor.workRoomIndex;

    if (workRoom == null) {
      survivor.state = SurvivorState.idle;
      survivor.isWorking = false;
      return;
    }

    // Zaten çalışma odasındaysa yürütme.
    if (!survivor.isMoving && survivor.currentRoomIndex == workRoom) {
      survivor.state = SurvivorState.working;
      survivor.isWorking = true;
      return;
    }

    // Çalışma odasına geri gönder.
    final success = _sendSurvivorToRoom(survivor, workRoom);

    if (!success) {
      survivor.state = SurvivorState.idle;
      survivor.isWorking = false;
    }
  }

  void _updateAutomaticNeeds(Survivor survivor, double dt) {
    /*
    if (survivor.hunger <= 25 && resourceManager.food >= 1) {
      debugPrint(
        'HUNGRY: ${survivor.name} '
        'moving=${survivor.isMoving} '
        'autoEating=${survivor.autoEating} '
        'autoDrinking=${survivor.autoDrinking} '
        'autoResting=${survivor.autoResting} '
        'foodReserved=${survivor.foodReserved} '
        'food=${resourceManager.food.toStringAsFixed(2)}',
      );
    }
    */

    if (survivor.isMoving) return;

    // Karakter odaya ulaştığında işlem süresini hesapla.
    if ((survivor.autoEating || survivor.autoDrinking) &&
        survivor.needActionDuration == 0) {
      final isWater = survivor.autoDrinking;

      survivor.needActionStartValue = isWater
          ? survivor.thirst
          : survivor.hunger;

      survivor.needActionDuration = _calculateNeedDuration(
        currentValue: survivor.needActionStartValue,
        isWater: isWater,
      );

      survivor.needActionTimer = 0;
    }

    // Su yoksa, kritik açlığı karşılayabilsin.
    if (survivor.autoDrinking &&
        !survivor.waterReserved &&
        resourceManager.water < 1 &&
        survivor.hunger <= 25 &&
        resourceManager.food >= 1) {
      survivor.autoDrinking = false;
      survivor.manualNeedAction = false;
      survivor.needRoomIndex = null;
      survivor.needActionTimer = 0;
      survivor.needActionDuration = 0;

      _startAutomaticNeed(survivor, isWater: false);
      return;
    }

    // Yemek yoksa, kritik susuzluğu karşılayabilsin.
    if (survivor.autoEating &&
        !survivor.foodReserved &&
        resourceManager.food < 1 &&
        survivor.thirst <= 25 &&
        resourceManager.water >= 1) {
      survivor.autoEating = false;
      survivor.manualNeedAction = false;
      survivor.needRoomIndex = null;
      survivor.needActionTimer = 0;
      survivor.needActionDuration = 0;

      _startAutomaticNeed(survivor, isWater: true);
      return;
    }

    // SU İÇME
    if (survivor.autoDrinking) {
      survivor.isWorking = false;

      // Henüz su ayrılmadıysa stoktan 1 birim al.
      if (!survivor.waterReserved) {
        if (!resourceManager.consumeWater(1)) {
          survivor.state = SurvivorState.waitingForWater;
          return;
        }

        survivor.waterReserved = true;

        // Bekleme sırasında susuzluk azalmış olabilir.
        survivor.needActionStartValue = survivor.thirst;
        survivor.needActionTimer = 0;
        survivor.needActionDuration = _calculateNeedDuration(
          currentValue: survivor.thirst,
          isWater: true,
        );
      }

      survivor.state = SurvivorState.drinking;
      survivor.needActionTimer += dt;

      _updateNeedProgress(survivor, isWater: true);

      if (survivor.needActionTimer >= survivor.needActionDuration) {
        survivor.thirst = 100;
        survivor.waterReserved = false;
        survivor.needActionTimer = 0;
        _finishAutomaticNeed(survivor);
      }

      return;
    }

    // YEMEK YEME
    if (survivor.autoEating) {
      survivor.isWorking = false;

      if (!survivor.foodReserved) {
        if (!resourceManager.consumeFood(1)) {
          survivor.state = SurvivorState.waitingForFood;
          return;
        }

        survivor.foodReserved = true;

        survivor.needActionStartValue = survivor.hunger;
        survivor.needActionTimer = 0;
        survivor.needActionDuration = _calculateNeedDuration(
          currentValue: survivor.hunger,
          isWater: false,
        );
      }

      survivor.state = SurvivorState.eating;
      survivor.needActionTimer += dt;

      _updateNeedProgress(survivor, isWater: false);

      if (survivor.needActionTimer >= survivor.needActionDuration) {
        survivor.hunger = 100;
        survivor.foodReserved = false;
        _finishAutomaticNeed(survivor);
      }

      return;
    }

    // Manuel dinlenme
    if (survivor.manualResting) {
      if (survivor.thirst <= 25 || survivor.hunger <= 25) {
        survivor.returnToManualRest = true;
        survivor.manualRestRoomIndex = survivor.currentRoomIndex;
        survivor.manualResting = false;
      } else {
        return;
      }
    }

    // Otomatik dinlenme
    if (survivor.autoResting) {
      final needsWater = survivor.thirst <= 25 && resourceManager.water >= 1;

      final needsFood = survivor.hunger <= 25 && resourceManager.food >= 1;

      if (!needsWater && !needsFood) {
        return;
      }

      final targetType = needsWater ? RoomType.water : RoomType.kitchen;

      // Oda doluysa dinlenmeye devam et.
      if (_findAvailableNeedRoom(survivor, targetType) == null) {
        return;
      }

      survivor.autoResting = false;
      survivor.restRoomIndex = null;
    }

    final needsWater = survivor.thirst <= 25 && resourceManager.water >= 1;

    final needsFood = survivor.hunger <= 25 && resourceManager.food >= 1;

    if (needsWater && needsFood) {
      // Değeri daha düşük olan ihtiyaç önce karşılanır.
      _startAutomaticNeed(survivor, isWater: survivor.thirst < survivor.hunger);
      return;
    }

    if (needsFood) {
      _startAutomaticNeed(survivor, isWater: false);
      return;
    }

    if (needsWater) {
      _startAutomaticNeed(survivor, isWater: true);
      return;
    }
  }

  void _updateNeedProgress(Survivor survivor, {required bool isWater}) {
    if (survivor.needActionDuration <= 0) return;

    // Kaynak önceden ayrılmış olmalı.
    if (isWater && !survivor.waterReserved) return;
    if (!isWater && !survivor.foodReserved) return;

    final progress = (survivor.needActionTimer / survivor.needActionDuration)
        .clamp(0.0, 1.0);

    final startValue = survivor.needActionStartValue.clamp(0.0, 100.0);

    final value = startValue + (100.0 - startValue) * progress;

    if (isWater) {
      survivor.thirst = value;
    } else {
      survivor.hunger = value;
    }
  }

  void _removeDeadSurvivors() {
    final deadSurvivors = survivors
        .where((survivor) => survivor.isDead)
        .toList();

    for (final survivor in deadSurvivors) {
      if (selectedCharacter.value == survivor) {
        selectedCharacter.value = null;
      }

      survivor.isWorking = false;
      survivor.assignedRoomIndex = null;
      survivor.workRoomIndex = null;
      survivor.restRoomIndex = null;
      survivor.needRoomIndex = null;

      survivor.removeFromParent();
      survivors.remove(survivor);

      _showDeathNotification(survivor.name);

      debugPrint('SURVIVOR DIED: ${survivor.name}');
    }
  }
}
