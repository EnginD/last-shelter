import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'resource_manager.dart';
import 'dart:collection';
import 'dart:math';
import '../models/survivor_candidate.dart';

import 'difficulty.dart';
import 'room.dart';
import 'survivor.dart';

class SurvivorNotifier extends ValueNotifier<Survivor?> {
  SurvivorNotifier() : super(null);

  void refresh() {
    notifyListeners();
  }
}

class ShelterGame extends FlameGame with TapCallbacks {
  final Difficulty difficulty;

  // Aynı tohum aynı oyunu üretir (testler için); null ise her oyun farklı.
  final int? seed;

  ShelterGame({this.difficulty = Difficulty.normal, this.seed});

  DifficultySettings get settings => difficulty.settings;

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
  final ValueNotifier<bool> isVictory = ValueNotifier<bool>(false);

  // Oyunun hedefi: 30 gün boyunca en az bir kişinin hayatta kalması.
  static const int targetDays = 30;

  // 1 oyun günü = 20 gerçek dakika.
  // Açlık ~6,25 dakikada bir öğün gerektirir → günde 3 öğün.
  static const double secondsPerDay = 20 * 60;

  // Gün 06:00'da başlar.
  static const double dayStartHour = 6;

  // Oyun başladığından beri geçen gerçek süre (saniye).
  double elapsedSeconds = 0;

  // 1'den başlayan gün numarası.
  int get currentDay =>
      (elapsedSeconds ~/ secondsPerDay + 1).clamp(1, targetDays);

  // Günün ne kadarının geçtiği (0.0 - 1.0).
  double get dayProgress => (elapsedSeconds % secondsPerDay) / secondsPerDay;

  // Oyun içi saat, örn. "14:35".
  String get clockText {
    final totalMinutes = ((dayStartHour + dayProgress * 24) * 60).floor();
    final hour = (totalMinutes ~/ 60) % 24;
    final minute = totalMinutes % 60;

    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  void _updateDayCounter(double dt) {
    elapsedSeconds += dt;

    if (elapsedSeconds < targetDays * secondsPerDay) return;

    elapsedSeconds = targetDays * secondsPerDay;

    if (survivors.isNotEmpty && !isGameOver.value) {
      isVictory.value = true;
      _refreshResourceText();
      debugPrint('VICTORY: $targetDays gün hayatta kalındı.');
    }
  }

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
      resourceManager.addFood(survivor.reservedAmount);
      survivor.foodReserved = false;
    }

    if (survivor.waterReserved) {
      resourceManager.addWater(survivor.reservedAmount);
      survivor.waterReserved = false;
    }

    survivor.reservedAmount = 0;
  }

  // İhtiyacı 100'e tamamlamak için gereken yemek/su miktarı.
  double _needCost(Survivor survivor, {required bool isWater}) {
    final value = (isWater ? survivor.thirst : survivor.hunger).clamp(
      0.0,
      100.0,
    );
    final perFull = isWater
        ? resourceManager.waterPerFullDrink
        : resourceManager.foodPerFullMeal;

    return (100.0 - value) / 100.0 * perFull;
  }

  // Stok tam ihtiyaca yetmese bile azıcık varsa kullanılabilir.
  static const double minNeedPortion = 0.1;

  bool _canAffordNeed(Survivor survivor, {required bool isWater}) {
    final stock = isWater ? resourceManager.water : resourceManager.food;
    final cost = _needCost(survivor, isWater: isWater);

    return stock >= min(cost, minNeedPortion);
  }

  // İhtiyaç miktarını stoktan ayırır; başarılıysa true döner.
  // Stok yetmezse kalanın hepsi alınır ve ihtiyaç orantılı dolar.
  bool _reserveNeed(Survivor survivor, {required bool isWater}) {
    if (!_canAffordNeed(survivor, isWater: isWater)) return false;

    final stock = isWater ? resourceManager.water : resourceManager.food;
    final amount = min(_needCost(survivor, isWater: isWater), stock);

    final consumed = isWater
        ? resourceManager.consumeWater(amount)
        : resourceManager.consumeFood(amount);

    if (!consumed) return false;

    final value = isWater ? survivor.thirst : survivor.hunger;
    final perFull = isWater
        ? resourceManager.waterPerFullDrink
        : resourceManager.foodPerFullMeal;

    survivor.reservedAmount = amount;
    survivor.needActionTarget = (value + amount / perFull * 100).clamp(
      0.0,
      100.0,
    );

    return true;
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

  double survivorEfficiency(Survivor survivor) {
    final health = _needMultiplier(survivor.health);
    final energy = _needMultiplier(survivor.energy);
    final hunger = _needMultiplier(survivor.hunger);
    final thirst = _needMultiplier(survivor.thirst);

    return (health + energy + hunger + thirst) / 4.0;
  }

  late final ResourceManager resourceManager = ResourceManager(settings);
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
      // Yemek yemek ve su içmek oda kapasitesine takılmaz.
      final success = _sendSurvivorToRoom(
        survivor,
        roomIndex,
        ignoreCapacity:
            action == SurvivorRoomAction.eat ||
            action == SurvivorRoomAction.drink,
      );
      if (!success) return;
    }

    // Önceki yemek/su rezervasyonunu temizle.
    _clearNeedReservations(survivor);

    // Önceki manuel/otomatik işlemleri temizle.
    survivor.autoEating = false;
    survivor.autoDrinking = false;
    survivor.autoResting = false;
    survivor.manualResting = false;

    // Oyuncu karakteri başka işe verdiyse tedavi iptal edilir;
    // aksi halde karakter "healing" durumunda takılı kalır.
    survivor.autoHealing = false;
    survivor.medicalRoomIndex = null;

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

    onMessage?.call(
      'Herkes yatakhanede. Bir karakter seçip odaya dokunarak görev ver.',
    );
  }

  double floorY(int floor) {
    return top + floor * (roomHeight + floorGap);
  }

  void _createRooms() {
    // 3. kat başlangıçta boştur; oyuncu buraya yeni oda inşa eder.
    const types = [
      RoomType.bedroom,
      RoomType.kitchen,
      RoomType.power,
      RoomType.water,
      RoomType.medical,
      RoomType.storage,
      RoomType.empty,
      RoomType.empty,
      RoomType.empty,
    ];

    for (int i = 0; i < types.length; i++) {
      final room = _createRoom(types[i], floor: i ~/ 3, column: i % 3);

      rooms.add(room);
      add(room);
    }
  }

  ShelterRoom _createRoom(
    RoomType type, {
    required int floor,
    required int column,
  }) {
    return ShelterRoom(
      type: type,
      floor: floor,
      column: column,
      position: Vector2(
        sideMargin + column * (roomWidth + sideMargin),
        floorY(floor),
      ),
      size: Vector2(roomWidth, roomHeight),
    );
  }

  // İNŞAAT SİSTEMİ

  // İnşaat bittiğinde veya iptal edildiğinde arayüze mesaj gönderir.
  void Function(String message)? onMessage;

  // Boş alana dokunulduğunda inşaat menüsünü açar.
  void Function(Survivor? survivor, int roomIndex)? onBuildRequested;

  // İptal edilen inşaatta maliyetin bu oranı geri verilir.
  static const double constructionRefundRatio = 0.5;

  // Zorluk seviyesine göre inşaat maliyeti.
  double buildCost(BuildOption option) =>
      option.electricityCost * settings.buildCostMultiplier;

  bool canAffordBuild(BuildOption option) =>
      resourceManager.electricity >= buildCost(option);

  // Maliyeti öder ve inşaatı başlatır; varsa seçili karakter inşaatçı olur.
  bool startConstruction(int roomIndex, BuildOption option, Survivor? builder) {
    final room = rooms[roomIndex];

    if (room.type != RoomType.empty || room.isUnderConstruction) return false;

    if (!resourceManager.consumeElectricity(buildCost(option))) {
      return false;
    }

    room.startConstruction(option);

    if (builder != null) {
      assignSurvivorToRoom(builder, roomIndex, SurvivorRoomAction.work);
    }

    _refreshResourceText();
    return true;
  }

  void joinConstruction(int roomIndex, Survivor survivor) {
    if (!rooms[roomIndex].isUnderConstruction) return;

    assignSurvivorToRoom(survivor, roomIndex, SurvivorRoomAction.work);
  }

  void cancelConstruction(int roomIndex) {
    final room = rooms[roomIndex];
    final option = room.construction;

    if (option == null) return;

    resourceManager.addElectricity(buildCost(option) * constructionRefundRatio);

    room.cancelConstruction();
    _releaseWorkers(roomIndex);
    _refreshResourceText();
  }

  void _updateConstruction(ShelterRoom room, Survivor builder, double dt) {
    final option = room.construction;
    if (option == null) return;

    final buildSeconds = option.buildHours * secondsPerDay / 24;

    // Her inşaatçı verimi oranında katkı sağlar; 3 kişi ~3 kat hızlı.
    room.constructionProgress += survivorEfficiency(builder) * dt / buildSeconds;
  }

  void _completeFinishedConstructions() {
    for (int i = 0; i < rooms.length; i++) {
      final site = rooms[i];
      final option = site.construction;

      if (option == null || site.constructionProgress < 1) continue;

      // Aynı sıraya yeni odayı koy; odalar indeksle tutulduğu için
      // karakterlerin oda bilgileri geçerli kalır.
      final room = _createRoom(
        option.type,
        floor: site.floor,
        column: site.column,
      );

      site.removeFromParent();
      rooms[i] = room;
      add(room);

      resourceManager.builtRooms++;

      // Üretim odası değilse inşaatçılar boşa çıkar.
      if (!_isWorkplace(room)) _releaseWorkers(i);

      onMessage?.call('🏗️ ${room.roomName} inşaatı tamamlandı!');
      debugPrint('CONSTRUCTION DONE: ${room.roomName}');
    }
  }

  // Odada çalışanların iş bağlantısını kaldırır.
  void _releaseWorkers(int roomIndex) {
    for (final survivor in survivors) {
      if (survivor.workRoomIndex == roomIndex) {
        survivor.workRoomIndex = null;
        survivor.isWorking = false;
      }
    }
  }

  bool _isWorkplace(ShelterRoom room) =>
      room.type == RoomType.power ||
      room.type == RoomType.water ||
      room.type == RoomType.kitchen ||
      room.isUnderConstruction;

  void _createStairs() {
    final lastFloor = rooms.map((r) => r.floor).reduce(max);

    final upperFloor = floorY(0) + roomHeight - 10;
    final lowerFloor = floorY(lastFloor) + roomHeight - 10;

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

    // Herkes yatakhanede, görevsiz başlar; işleri oyuncu belirler.
    final bedroomIndex = rooms.indexWhere(
      (room) => room.type == RoomType.bedroom,
    );
    final room = rooms[bedroomIndex];

    // Beceriler zorluğa göre rastgele; oyuncu buna göre görev dağıtır.
    final profiles = settings.generateStarters(_random, names.length);

    for (int i = 0; i < names.length; i++) {
      final survivor = Survivor(
        name: names[i],
        currentFloor: room.floor,
        position: _slotPosition(room, i),
      );

      survivor.electricitySkill = profiles[i].electricitySkill;
      survivor.waterSkill = profiles[i].waterSkill;
      survivor.cookingSkill = profiles[i].cookingSkill;
      survivor.health = profiles[i].health.toDouble();

      survivor.assignedRoomIndex = bedroomIndex;
      survivor.currentRoomIndex = bedroomIndex;

      occupantSlot[survivor] = i;

      survivor.isSelected = i == selectedSurvivor;
      survivor.starvationDamageMultiplier = settings.starvationDamageMultiplier;

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
        '📅 Gün $currentDay/$targetDays  🕒 $clockText\n'
        '⚡ ${resourceManager.electricity.floor()} '
        '${_resourceTrend(resourceManager.electricityNetPerMinute)}\n'
        '💧 ${resourceManager.water.floor()} '
        '${_resourceTrend(resourceManager.waterNetPerMinute)}\n'
        '🍞 ${resourceManager.food.floor()} '
        '${_resourceTrend(resourceManager.foodNetPerMinute)}\n'
        '👥 ${survivors.length}/$totalBeds';
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

      final hasSelection =
          selectedSurvivor >= 0 && selectedSurvivor < survivors.length;

      // Boş alan: karakter seçili olmasa da inşaat menüsü açılır.
      if (room.type == RoomType.empty) {
        onBuildRequested?.call(
          hasSelection ? survivors[selectedSurvivor] : null,
          i,
        );
        return;
      }

      if (!hasSelection) return;

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
    if (isGameOver.value || isVictory.value) return;

    super.update(dt);

    double electricityProduction = 0;
    double waterProduction = 0;
    double foodProduction = 0;

    for (final survivor in survivors) {
      _updateAutomaticBehavior(survivor);
      _updateAutomaticNeeds(survivor, dt);

      survivor.updateEnergy(dt);
      survivor.updateNeeds(dt);
      survivor.checkDeath();

      if (survivor.isDead) continue;

      _updateAutomaticHealing(survivor, dt);

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
      final efficiency = survivorEfficiency(survivor);

      // Elektrik yoksa su arıtma durur, mutfak yavaşlar.
      final power = resourceManager.powerMultiplier;
      final waterPower = resourceManager.waterPowerMultiplier;

      // Dakikalık temel üretim. Bir işçi uyku/yemek molalarıyla
      // zamanın ~%52'sinde çalışır.
      switch (room.type) {
        case RoomType.power:
          electricityProduction +=
              3.0 * _skillMultiplier(survivor.electricitySkill) * efficiency;
          break;

        case RoomType.water:
          waterProduction +=
              1.5 *
              _skillMultiplier(survivor.waterSkill) *
              efficiency *
              waterPower;
          break;

        case RoomType.kitchen:
          foodProduction +=
              1.2 *
              _skillMultiplier(survivor.cookingSkill) *
              efficiency *
              power;
          break;

        case RoomType.empty:
          _updateConstruction(room, survivor, dt);
          break;

        default:
          break;
      }
    }

    _completeFinishedConstructions();

    // Zorluk seviyesine göre üretim çarpanı.
    final productionMultiplier = settings.productionMultiplier;

    resourceManager.updateProduction(
      electricity: electricityProduction * productionMultiplier,
      water: waterProduction * productionMultiplier,
      food: foodProduction * productionMultiplier,
    );

    resourceManager.updateResources(dt);

    resourceUiTimer += dt;

    _removeDeadSurvivors();

    // Son karakter öldüyse Game Over.
    _checkGameOver();

    // Ölüm kontrolünden sonra gün ilerlesin; aynı karede
    // son kişi öldüyse zafer verilmez.
    _updateDayCounter(dt);
    _updateVisitors(dt);

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

      // Flutter arayüzünü her karede değil, 0,5 saniyede bir yenile.
      uiRefresh.value++;

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

  // Odanın kapasitesini kullananlar: çalışanlar, uyuyanlar, tedavi olanlar.
  // Yemek yemeye veya su içmeye gelenler kapasiteye sayılmaz.
  int _occupantCount(int roomIndex, Survivor except) => survivors
      .where(
        (s) =>
            s != except &&
            s.assignedRoomIndex == roomIndex &&
            !s.autoEating &&
            !s.autoDrinking,
      )
      .length;

  // Karakter otomatik bir işe (yemek, dinlenme, tedavi) giderken
  // işten ayrılıyorsa geri döneceği iş yerini hatırla.
  void _rememberWorkRoom(Survivor survivor) {
    final assigned = survivor.assignedRoomIndex;

    if (survivor.workRoomIndex != null || assigned == null) return;

    if (_isWorkplace(rooms[assigned])) survivor.workRoomIndex = assigned;
  }

  int? _findAvailableBedroom(Survivor survivor) {
    for (int i = 0; i < rooms.length; i++) {
      final room = rooms[i];

      if (room.type != RoomType.bedroom) continue;

      if (_occupantCount(i, survivor) < room.capacity) {
        return i;
      }
    }

    return null;
  }

  bool _sendSurvivorToRoom(
    Survivor survivor,
    int roomIndex, {
    bool ignoreCapacity = false,
  }) {
    final room = rooms[roomIndex];

    if (!ignoreCapacity && _occupantCount(roomIndex, survivor) >= room.capacity) {
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

  void _startAutomaticHealing(Survivor survivor) {
    if (survivor.isDead ||
        survivor.isMoving ||
        survivor.autoHealing ||
        survivor.autoEating ||
        survivor.autoDrinking) {
      return;
    }

    final medicalIndex = _findAvailableNeedRoom(survivor, RoomType.medical);

    if (medicalIndex == null) return;

    final previousWorkRoom = survivor.workRoomIndex;
    final previousAssignedRoom = survivor.assignedRoomIndex;

    // Önceki görevini koru.
    _rememberWorkRoom(survivor);

    final alreadyInRoom = survivor.currentRoomIndex == medicalIndex;

    if (!alreadyInRoom) {
      final success = _sendSurvivorToRoom(survivor, medicalIndex);

      if (!success) {
        survivor.workRoomIndex = previousWorkRoom;
        survivor.assignedRoomIndex = previousAssignedRoom;
        return;
      }
    }

    survivor.autoResting = false;
    survivor.restRoomIndex = null;
    survivor.autoHealing = true;
    survivor.medicalRoomIndex = medicalIndex;
    survivor.isWorking = false;

    survivor.state = alreadyInRoom
        ? SurvivorState.healing
        : SurvivorState.goingToMedical;
  }

  void _updateAutomaticHealing(Survivor survivor, double dt) {
    if (!survivor.autoHealing || survivor.isDead) return;
    if (survivor.isMoving) return;

    if (survivor.currentRoomIndex != survivor.medicalRoomIndex) {
      return;
    }

    survivor.state = SurvivorState.healing;
    survivor.isWorking = false;

    // Açlık ve susuzluk tedavi hızını etkiler.
    double healingMultiplier = 1.0;

    if (survivor.hunger <= 0 || survivor.thirst <= 0) {
      healingMultiplier = 0.0;
    } else if (survivor.hunger < 25 || survivor.thirst < 25) {
      healingMultiplier = 0.25;
    } else if (survivor.hunger < 50 || survivor.thirst < 50) {
      healingMultiplier = 0.5;
    }

    // Elektrik yoksa revir yavaş çalışır.
    healingMultiplier *= resourceManager.powerMultiplier;

    // Normal koşullarda dakikada 120 sağlık puanı.
    const double healingPerMinute = 120.0;

    survivor.health += healingPerMinute * healingMultiplier * dt / 60.0;

    survivor.health = survivor.health.clamp(0.0, 100.0);

    if (survivor.health >= 100) {
      survivor.health = 100;
      _finishAutomaticHealing(survivor);
    }
  }

  void _finishAutomaticHealing(Survivor survivor) {
    survivor.autoHealing = false;
    survivor.medicalRoomIndex = null;

    final workRoom = survivor.workRoomIndex;

    if (workRoom == null) {
      survivor.state = SurvivorState.idle;
      survivor.isWorking = false;
      return;
    }

    if (survivor.currentRoomIndex == workRoom) {
      survivor.state = SurvivorState.working;
      survivor.isWorking = true;
      return;
    }

    final success = _sendSurvivorToRoom(survivor, workRoom);

    if (!success) {
      survivor.state = SurvivorState.idle;
      survivor.isWorking = false;
    }
  }

  void _startAutomaticRest(Survivor survivor) {
    final bedroomIndex = _findAvailableBedroom(survivor);

    if (bedroomIndex == null) {
      survivor.state = SurvivorState.waitingForBed;
      survivor.isWorking = false;
      return;
    }

    _rememberWorkRoom(survivor);

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

    // Tedavi devam ediyorsa diğer otomatik davranışları başlatma.
    if (survivor.autoHealing) {
      survivor.isWorking = false;
      survivor.state = SurvivorState.healing;
      return;
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

    // Sağlık kritikse revire git.
    if (survivor.health <= 25 &&
        survivor.hunger > 25 &&
        survivor.thirst > 25 &&
        !survivor.autoEating &&
        !survivor.autoDrinking) {
      _startAutomaticHealing(survivor);
      if (survivor.autoHealing) return;
    }

    // Kritik enerji kontrolü
    if (survivor.energy <= 25 && survivor.workRoomIndex != null) {
      final canDrink =
          survivor.thirst <= 25 && _canAffordNeed(survivor, isWater: true);

      final canEat =
          survivor.hunger <= 25 && _canAffordNeed(survivor, isWater: false);

      // Önce karşılanabilecek kritik yemek/su ihtiyacını gider.
      if (!canDrink && !canEat) {
        _startAutomaticRest(survivor);
        return;
      }
    }

    // Enerji kritik seviyedeyse ve yatak bulunamıyorsa
    // normal çalışmaya geri dönmesin.
    if (survivor.energy <= 25 &&
        survivor.workRoomIndex != null &&
        survivor.state == SurvivorState.waitingForBed) {
      survivor.isWorking = false;
      return;
    }

    // Normal çalışma
    if (survivor.assignedRoomIndex != null) {
      final room = rooms[survivor.assignedRoomIndex!];

      if (_isWorkplace(room)) {
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

  // Her kişinin bir yatağı olur; nüfus sınırı toplam yatak sayısıdır.
  int get totalBeds => rooms
      .where((room) => room.type == RoomType.bedroom)
      .fold(0, (sum, room) => sum + room.capacity);

  bool get hasFreeBed => survivors.length < totalBeds;

  // ZİYARETÇİ SİSTEMİ
  // İlk ziyaretçi 2. gün gelir, sonrası her 1-2 günde bir.
  // Oyuncunun karar vermek için 1 oyun saati vardır.
  double get visitorResponseSeconds =>
      settings.visitorResponseMinutes / (24 * 60) * secondsPerDay;

  final ValueNotifier<SurvivorCandidate?> pendingVisitor =
      ValueNotifier<SurvivorCandidate?>(null);

  late final Random _random = Random(seed);

  late double nextVisitorAt = secondsPerDay * (1 + _random.nextDouble() * 0.25);

  double visitorTimeLeft = 0;

  // Kararın kalan süresi, oyun dakikası olarak.
  int get visitorMinutesLeft =>
      (visitorTimeLeft / secondsPerDay * 24 * 60).ceil();

  void _updateVisitors(double dt) {
    if (pendingVisitor.value != null) {
      visitorTimeLeft -= dt;

      // Süre dolarsa ziyaretçi gider.
      if (visitorTimeLeft <= 0) _dismissVisitor();
      return;
    }

    if (elapsedSeconds < nextVisitorAt) return;

    pendingVisitor.value = SurvivorCandidate.random(
      injuredChance: settings.visitorInjuredChance,
      carryChance: settings.visitorCarryChance,
      random: _random,
    );
    visitorTimeLeft = visitorResponseSeconds;
  }

  void _dismissVisitor() {
    pendingVisitor.value = null;
    visitorTimeLeft = 0;
    final days =
        settings.visitorMinDays +
        _random.nextDouble() * (settings.visitorMaxDays - settings.visitorMinDays);

    nextVisitorAt = elapsedSeconds + secondsPerDay * days;
  }

  bool acceptVisitor() {
    final candidate = pendingVisitor.value;

    if (candidate == null || !addNewSurvivor(candidate)) return false;

    resourceManager.addFood(candidate.food.toDouble());
    resourceManager.addWater(candidate.water.toDouble());

    _dismissVisitor();
    _refreshResourceText();
    return true;
  }

  void rejectVisitor() {
    if (pendingVisitor.value == null) return;

    _dismissVisitor();
  }

  bool addNewSurvivor(SurvivorCandidate candidate) {
    if (!hasFreeBed) return false;

    final bedroomIndex = rooms.indexWhere(
      (room) => room.type == RoomType.bedroom,
    );

    if (bedroomIndex == -1) return false;

    final room = rooms[bedroomIndex];

    final survivor = Survivor(
      name: candidate.name,
      currentFloor: room.floor,
      position: Vector2.zero(),
    );

    survivor.health = candidate.health.toDouble();
    survivor.starvationDamageMultiplier = settings.starvationDamageMultiplier;

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

      // Yemekhane ve su odası herkese hizmet eder; işçilerle dolu olsa da
      // yemek/su alınabilir. Revirde ise sedye sayısı sınırlıdır.
      if (type == RoomType.kitchen || type == RoomType.water) return i;

      if (_occupantCount(i, survivor) < room.capacity) {
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
    final consumed = _reserveNeed(survivor, isWater: isWater);

    if (!consumed) return;

    final previousWorkRoom = survivor.workRoomIndex;
    final previousAssignedRoom = survivor.assignedRoomIndex;

    _rememberWorkRoom(survivor);

    final alreadyInRoom = survivor.currentRoomIndex == roomIndex;

    if (!alreadyInRoom) {
      final success = _sendSurvivorToRoom(
        survivor,
        roomIndex,
        ignoreCapacity: true,
      );

      if (!success) {
        // Hareket başlatılamadıysa kaynağı iade et.
        if (isWater) {
          resourceManager.addWater(survivor.reservedAmount);
        } else {
          resourceManager.addFood(survivor.reservedAmount);
        }

        survivor.reservedAmount = 0;

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

      survivor.autoEating = false;
      survivor.autoDrinking = false;
      survivor.needRoomIndex = null;

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

    // Tedavi sırasında yemek/su için yeni hareket başlatma.
    // Açlık/susuzluk kritikse ve karşılanabiliyorsa tedavi bırakılır;
    // aksi halde karakter revirde açlıktan ölebilir.
    if (survivor.autoHealing) {
      final criticalNeed =
          (survivor.thirst <= 25 && _canAffordNeed(survivor, isWater: true)) ||
          (survivor.hunger <= 25 && _canAffordNeed(survivor, isWater: false));

      if (!criticalNeed) return;

      survivor.autoHealing = false;
      survivor.medicalRoomIndex = null;
    }

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
        !_canAffordNeed(survivor, isWater: true) &&
        survivor.hunger <= 25 &&
        _canAffordNeed(survivor, isWater: false)) {
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
        !_canAffordNeed(survivor, isWater: false) &&
        survivor.thirst <= 25 &&
        _canAffordNeed(survivor, isWater: true)) {
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
        if (!_reserveNeed(survivor, isWater: true)) {
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
        survivor.thirst = survivor.needActionTarget;
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
        if (!_reserveNeed(survivor, isWater: false)) {
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
        survivor.hunger = survivor.needActionTarget;
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
      final needsWater =
          survivor.thirst <= 25 && _canAffordNeed(survivor, isWater: true);

      final needsFood =
          survivor.hunger <= 25 && _canAffordNeed(survivor, isWater: false);

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

    final needsWater =
        survivor.thirst <= 25 && _canAffordNeed(survivor, isWater: true);

    final needsFood =
        survivor.hunger <= 25 && _canAffordNeed(survivor, isWater: false);

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

    final target = max(survivor.needActionTarget, startValue);
    final value = startValue + (target - startValue) * progress;

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

      // Yola çıkarken ayırdığı yemek/su depoya geri döner.
      _clearNeedReservations(survivor);

      survivor.isWorking = false;
      survivor.assignedRoomIndex = null;
      survivor.workRoomIndex = null;
      survivor.restRoomIndex = null;
      survivor.needRoomIndex = null;

      occupantSlot.remove(survivor);
      destinationRooms.remove(survivor);

      survivor.removeFromParent();
      survivors.remove(survivor);

      _showDeathNotification(survivor.name);

      debugPrint('SURVIVOR DIED: ${survivor.name}');
    }

    if (deadSurvivors.isEmpty) return;

    // Liste kaydığı için seçili karakterin indeksini yeniden bul.
    // Seçili karakter öldüyse -1 olur ve oda tıklamaları yok sayılır.
    selectedSurvivor = survivors.indexWhere((s) => s.isSelected);

    resourceManager.population = survivors.length;
    _refreshResourceText();
  }
}
