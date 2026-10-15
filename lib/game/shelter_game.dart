import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'resource_manager.dart';
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

  int selectedSurvivor = 0;
  int nextSurvivorId = 4;

  static const double roomHeight = 145;
  static const double roomGap = 8;
  static const double floorGap = 42;
  static const double sideMargin = 10;

  double roomWidth = 0;
  double top = 0;
  double stairX = 0;

  double _skillMultiplier(int skill) {
    return 0.5 + skill.clamp(0, 100) / 100.0;
  }

  final ResourceManager resourceManager = ResourceManager();
  final Map<Survivor, int> destinationRooms = {};

  double resourceUiTimer = 0;
  TextComponent? resourceText;

  @override
  Color backgroundColor() => const Color(0xFF171B20);

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
        '⚡ ${resourceManager.electricity.toStringAsFixed(0)} '
        '${_resourceTrend(resourceManager.electricityNetPerMinute)}\n'
        '💧 ${resourceManager.water.toStringAsFixed(0)} '
        '${_resourceTrend(resourceManager.waterNetPerMinute)}\n'
        '🍞 ${resourceManager.food.toStringAsFixed(0)} '
        '${_resourceTrend(resourceManager.foodNetPerMinute)}\n'
        '👥 ${survivors.length}/${resourceManager.maxPopulation}';
  }

  List<Vector2> _buildPath(Survivor survivor, ShelterRoom targetRoom) {
    final destination = targetRoom.standingPosition;

    // Aynı kattaysa doğrudan ilerle.
    if (survivor.currentFloor == targetRoom.floor) {
      return [destination];
    }

    // Önce bulunduğu kattaki merdivene git.
    final currentStair = Vector2(stairX, survivor.position.y);

    // Merdivenden hedef kata geç.
    final targetStair = Vector2(
      stairX,
      targetRoom.position.y + targetRoom.size.y - 10,
    );

    // Sonra hedef odaya ilerle.
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

    // Oda seçimi ve görevlendirme
    for (int i = 0; i < rooms.length; i++) {
      final room = rooms[i];

      if (room.toRect().contains(tap.toOffset())) {
        final survivor = survivors[selectedSurvivor];

        final success = _sendSurvivorToRoom(survivor, i);

        if (success) {
          // Oyuncunun komutu otomatik dinlenmeyi iptal eder.
          survivor.autoResting = false;
          survivor.restRoomIndex = null;

          // Oyuncunun komutu otomatik yemek/su işlemini iptal eder.
          survivor.autoEating = false;
          survivor.autoDrinking = false;
          survivor.needRoomIndex = null;
          survivor.needActionTimer = 0;

          // Yeni çalışma odasını kaydet.
          if (room.type == RoomType.power ||
              room.type == RoomType.water ||
              room.type == RoomType.kitchen) {
            survivor.workRoomIndex = i;
          } else {
            survivor.workRoomIndex = null;
          }
        }
        return;
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    double electricityProduction = 0;
    double waterProduction = 0;
    double foodProduction = 0;

    for (final survivor in survivors) {
      // Önce hedef odaya varış ve otomatik davranışlar.
      _updateAutomaticBehavior(survivor);
      _updateAutomaticNeeds(survivor, dt);

      // Enerji ve ihtiyaçları bir kez güncelle.
      survivor.updateEnergy(dt);
      survivor.updateNeeds(dt);

      // Yalnızca çalışan karakterler üretim yapar.
      if (survivor.isMoving ||
          survivor.autoResting ||
          survivor.autoEating ||
          survivor.autoDrinking ||
          !survivor.isWorking ||
          survivor.assignedRoomIndex == null) {
        continue;
      }

      final room = rooms[survivor.assignedRoomIndex!];

      switch (room.type) {
        case RoomType.power:
          electricityProduction +=
              6.0 * _skillMultiplier(survivor.electricitySkill);
          break;

        case RoomType.water:
          waterProduction += 5.0 * _skillMultiplier(survivor.waterSkill);
          break;

        case RoomType.kitchen:
          foodProduction += 4.0 * _skillMultiplier(survivor.cookingSkill);
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

    // Otomatik dinlenme süreci
    if (survivor.autoResting) {
      if (survivor.restRoomIndex != null &&
          survivor.currentRoomIndex == survivor.restRoomIndex) {
        survivor.state = SurvivorState.sleeping;
        survivor.isWorking = false;

        if (survivor.energy >= 95) {
          _finishAutomaticRest(survivor);
        }
      }

      return;
    }

    // Yorgunluk kontrolü
    if (survivor.energy <= 20 && survivor.workRoomIndex != null) {
      _startAutomaticRest(survivor);
      return;
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
    final roomType = isWater ? RoomType.water : RoomType.kitchen;

    final roomIndex = _findAvailableNeedRoom(survivor, roomType);

    if (roomIndex == null) return;

    // Karakterin asıl görevini koru.
    survivor.workRoomIndex ??= survivor.assignedRoomIndex;

    final success = _sendSurvivorToRoom(survivor, roomIndex);

    if (!success) return;

    survivor.autoEating = !isWater;
    survivor.autoDrinking = isWater;
    survivor.needRoomIndex = roomIndex;
    survivor.needActionTimer = 0;
  }

  void _finishAutomaticNeed(Survivor survivor) {
    final workRoom = survivor.workRoomIndex;

    survivor.autoEating = false;
    survivor.autoDrinking = false;
    survivor.needRoomIndex = null;

    if (workRoom == null) {
      survivor.state = SurvivorState.idle;
      return;
    }

    _sendSurvivorToRoom(survivor, workRoom);
  }

  void _updateAutomaticNeeds(Survivor survivor, double dt) {
    if (survivor.isMoving) return;

    // Su içme
    if (survivor.autoDrinking) {
      survivor.state = SurvivorState.drinking;
      survivor.isWorking = false;

      survivor.needActionTimer += dt;

      if (survivor.needActionTimer >= 5.0) {
        if (resourceManager.consumeWater(1)) {
          survivor.thirst = 100;
          survivor.needActionTimer = 0;
          _finishAutomaticNeed(survivor);
        } else {
          survivor.state = SurvivorState.waitingForWater;
        }
      }
      return;
    }

    // Yemek yeme
    if (survivor.autoEating) {
      survivor.state = SurvivorState.eating;
      survivor.isWorking = false;

      survivor.needActionTimer += dt;

      if (survivor.needActionTimer >= 8.0) {
        if (resourceManager.consumeFood(1)) {
          survivor.hunger = 100;
          survivor.needActionTimer = 0;
          _finishAutomaticNeed(survivor);
        } else {
          survivor.state = SurvivorState.waitingForFood;
        }
      }
      return;
    }

    // Uyurken yeni ihtiyaç başlatma.
    if (survivor.autoResting) return;

    // Önce susuzluk kontrolü.
    if (survivor.thirst <= 25) {
      _startAutomaticNeed(survivor, isWater: true);
      return;
    }

    // Ardından açlık kontrolü.
    if (survivor.hunger <= 25) {
      _startAutomaticNeed(survivor, isWater: false);
    }
  }
}
