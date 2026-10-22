// 30 günlük denge simülasyonu.
//
// Oyun ekran olmadan hızlandırılmış olarak çalıştırılır. Her zorluk farklı
// tohumlarla (rastgele başlangıç becerileri ve ziyaretçiler) birkaç kez
// oynanır.
//
// "Pasif oyuncu": becerilere bakmadan herkesi sabit sırayla üretime koyar
// (Ayşe mutfak, Mehmet elektrik, Ahmet su), sonra hiçbir şey yapmaz.
//
// "Aktif oyuncu": başlangıçta becerilere göre en iyi dağılımı seçer, boş
// yatak varsa ziyaretçileri kabul eder, boşta kalanı en kritik odaya koyar
// ve yatak dolunca yatakhane inşa eder.
//
// Çalıştırmak için: flutter test test/simulation_test.dart

import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_shelter/game/difficulty.dart';
import 'package:last_shelter/game/room.dart';
import 'package:last_shelter/game/shelter_game.dart';
import 'package:last_shelter/game/survivor.dart';

const double stepSeconds = 0.2;
const int runsPerScenario = 10;

// Aktif oyuncunun kararlarını kontrol etme aralığı (1 oyun saati).
const double decisionSeconds = ShelterGame.secondsPerDay / 24;

// Yatakhane inşa ederken elde tutulacak en az elektrik.
const double buildElectricityReserve = 30;

// Bir işçinin molalar ve verim dahil ortalama çalışma oranı (ölçülen ~%52,
// verim ~0,9).
const double effectiveWorkRatio = 0.47;

class SimulationResult {
  final Difficulty difficulty;
  final bool active;
  final int seed;

  bool victory = false;
  int acceptedVisitors = 0;
  int builtRooms = 0;
  double? firstDeathDay;
  double? gameOverDay;
  double? noPowerDay;
  double? noFoodDay;
  double? noWaterDay;
  int survivorsAtEnd = 0;
  String starters = '';

  SimulationResult(this.difficulty, this.seed, {required this.active});

  static String _day(double? day) =>
      day == null ? '-' : day.toStringAsFixed(1);

  @override
  String toString() =>
      '${(active ? 'aktif' : 'pasif').padRight(6)}'
      '${difficulty.settings.label.padRight(7)}'
      '#${'$seed'.padRight(3)}'
      '${(victory ? 'KAZANDI' : 'KAYBETTİ').padRight(9)}'
      'son: ${'$survivorsAtEnd'.padRight(3)}'
      '${active ? '+${'$acceptedVisitors'.padRight(2)} ziy. ${'$builtRooms'.padRight(1)} oda  ' : '                 '}'
      'ölüm: ${_day(firstDeathDay).padRight(5)}'
      'bitiş: ${_day(gameOverDay).padRight(5)}'
      '⚡0: ${_day(noPowerDay).padRight(5)}'
      '🍞0: ${_day(noFoodDay).padRight(5)}'
      '💧0: ${_day(noWaterDay).padRight(5)}'
      '$starters';
}

Future<ShelterGame> _startGame(
  WidgetTester tester,
  Difficulty difficulty,
  int seed,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));

  final game = ShelterGame(difficulty: difficulty, seed: seed);
  await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
  await tester.pump();
  await tester.pump();

  return game;
}

int _roomOf(ShelterGame game, RoomType type) =>
    game.rooms.indexWhere((room) => room.type == type);

double _skillMultiplier(int skill) => 0.5 + skill.clamp(0, 100) / 100.0;

// Üretim odaları: (oda türü, işçi başı temel üretim)
const productionRooms = [
  (RoomType.power, 3.0),
  (RoomType.water, 1.5),
  (RoomType.kitchen, 1.2),
];

int _skillFor(Survivor survivor, RoomType type) => switch (type) {
  RoomType.power => survivor.electricitySkill,
  RoomType.water => survivor.waterSkill,
  _ => survivor.cookingSkill,
};

// Verilen görev dağılımıyla en erken bitecek kaynağın kalan süresi
// (dakika). Hiçbir kaynak bitmiyorsa sonsuz.
double _bottleneckMinutes(
  ShelterGame game,
  Map<Survivor, RoomType> assignment,
) {
  final resources = game.resourceManager;
  final production = game.settings.productionMultiplier;

  double worst = double.infinity;

  for (final (type, perWorker) in productionRooms) {
    double produced = 0;

    for (final MapEntry(key: survivor, value: room) in assignment.entries) {
      if (room != type) continue;

      produced +=
          perWorker *
          _skillMultiplier(_skillFor(survivor, type)) *
          production *
          effectiveWorkRatio;
    }

    final (consumption, stock) = switch (type) {
      RoomType.power => (
        resources.electricityConsumptionPerMinute,
        resources.electricity,
      ),
      RoomType.water => (resources.waterConsumptionPerMinute, resources.water),
      _ => (resources.foodConsumptionPerMinute, resources.food),
    };

    final net = produced - consumption;
    if (net < 0) worst = min(worst, stock / -net);
  }

  return worst;
}

// Şu an üretimde çalışan herkesin görev dağılımı.
Map<Survivor, RoomType> _currentAssignment(ShelterGame game) => {
  for (final survivor in game.survivors)
    if (survivor.workRoomIndex != null &&
        productionRooms.any(
          (r) => r.$1 == game.rooms[survivor.workRoomIndex!].type,
        ))
      survivor: game.rooms[survivor.workRoomIndex!].type,
};

// Darboğazı en çok rahatlatan, yeri olan üretim odasına yerleştirir.
void _assignToNeediestRoom(ShelterGame game, Survivor survivor) {
  final current = _currentAssignment(game)..remove(survivor);

  int? bestRoom;
  double bestScore = -1;
  int bestSkill = -1;

  for (final (type, _) in productionRooms) {
    final roomIndex = _roomOf(game, type);
    final workers = current.values.where((t) => t == type).length;

    if (workers >= game.rooms[roomIndex].capacity) continue;

    final score = _bottleneckMinutes(game, {...current, survivor: type});
    final skill = _skillFor(survivor, type);

    // Önce darboğaz, eşitlikte (ör. her şey artıda) en iyi beceri.
    if (score > bestScore || (score == bestScore && skill > bestSkill)) {
      bestRoom = roomIndex;
      bestScore = score;
      bestSkill = skill;
    }
  }

  if (bestRoom != null) {
    game.assignSurvivorToRoom(survivor, bestRoom, SurvivorRoomAction.work);
  }
}

// Başlangıç kadrosu için olası tüm dağılımları dener.
void _assignStartersBySkill(ShelterGame game) {
  final starters = game.survivors.toList();
  final types = productionRooms.map((r) => r.$1).toList();

  Map<Survivor, RoomType>? best;
  double bestScore = -1;
  int bestSkill = -1;

  for (final perm in _permutations(types)) {
    final assignment = {
      for (int i = 0; i < starters.length; i++) starters[i]: perm[i],
    };

    final score = _bottleneckMinutes(game, assignment);
    final skill = assignment.entries
        .map((e) => _skillFor(e.key, e.value))
        .reduce((a, b) => a + b);

    if (score > bestScore || (score == bestScore && skill > bestSkill)) {
      best = assignment;
      bestScore = score;
      bestSkill = skill;
    }
  }

  for (final MapEntry(key: survivor, value: type) in best!.entries) {
    game.assignSurvivorToRoom(
      survivor,
      _roomOf(game, type),
      SurvivorRoomAction.work,
    );
  }
}

List<List<T>> _permutations<T>(List<T> items) {
  if (items.length <= 1) return [items];

  return [
    for (int i = 0; i < items.length; i++)
      for (final rest in _permutations([
        ...items.sublist(0, i),
        ...items.sublist(i + 1),
      ]))
        [items[i], ...rest],
  ];
}

// Yatak doluysa ve elektrik yetiyorsa yatakhane inşa eder.
// İnşaatçı, çıkarılınca darboğazı en az kötüleştiren işçidir.
bool _maybeBuildBedroom(ShelterGame game) {
  if (game.hasFreeBed) return false;
  if (game.rooms.any((room) => room.isUnderConstruction)) return false;

  final site = game.rooms.indexWhere((room) => room.type == RoomType.empty);
  if (site == -1) return false;

  final option = ShelterRoom.buildOptions.firstWhere(
    (o) => o.type == RoomType.bedroom,
  );

  if (game.resourceManager.electricity <
      game.buildCost(option) + buildElectricityReserve) {
    return false;
  }

  final current = _currentAssignment(game);
  if (current.length < 2) return false;

  Survivor? builder;
  double bestScore = -1;

  for (final candidate in current.keys) {
    final score = _bottleneckMinutes(game, {...current}..remove(candidate));

    if (score > bestScore) {
      bestScore = score;
      builder = candidate;
    }
  }

  return game.startConstruction(site, option, builder);
}

void _setupPassive(ShelterGame game) {
  final [ahmet, ayse, mehmet] = game.survivors;

  game.assignSurvivorToRoom(
    ayse,
    _roomOf(game, RoomType.kitchen),
    SurvivorRoomAction.work,
  );
  game.assignSurvivorToRoom(
    mehmet,
    _roomOf(game, RoomType.power),
    SurvivorRoomAction.work,
  );
  game.assignSurvivorToRoom(
    ahmet,
    _roomOf(game, RoomType.water),
    SurvivorRoomAction.work,
  );
}

String _describeStarters(ShelterGame game) => game.survivors
    .map(
      (s) =>
          ' ${s.name.substring(0, 2)}:${s.electricitySkill}/${s.waterSkill}/${s.cookingSkill}'
          '${s.health < 100 ? '♥${s.health.floor()}' : ''}',
    )
    .join();

Future<SimulationResult> _simulate(
  WidgetTester tester,
  Difficulty difficulty,
  int seed, {
  required bool active,
}) async {
  final game = await _startGame(tester, difficulty, seed);
  final result = SimulationResult(difficulty, seed, active: active);
  result.starters = _describeStarters(game);

  if (active) {
    _assignStartersBySkill(game);
  } else {
    _setupPassive(game);
  }

  final resources = game.resourceManager;
  double day() => game.elapsedSeconds / ShelterGame.secondsPerDay;

  final totalSteps =
      (ShelterGame.targetDays * ShelterGame.secondsPerDay / stepSeconds).ceil() +
      10;

  final decisionEvery = (decisionSeconds / stepSeconds).round();

  final traceDeaths = const bool.fromEnvironment('TRACE_DEATHS');
  final snapshot = <Survivor, String>{};

  for (int step = 0; step < totalSteps; step++) {
    final aliveBefore = game.survivors.length;

    if (traceDeaths) {
      for (final s in game.survivors) {
        snapshot[s] =
            '${s.name} H=${s.health.toStringAsFixed(0)} '
            'hu=${s.hunger.toStringAsFixed(0)} th=${s.thirst.toStringAsFixed(0)} '
            'en=${s.energy.toStringAsFixed(0)} st=${s.state.name} '
            'room=${s.assignedRoomIndex}/${s.currentRoomIndex} work=${s.workRoomIndex} '
            'aE=${s.autoEating} aD=${s.autoDrinking} aR=${s.autoResting} '
            'aH=${s.autoHealing} mov=${s.isMoving} '
            'food=${resources.food.toStringAsFixed(1)} water=${resources.water.toStringAsFixed(1)}';
      }
    }

    final before = game.survivors.toList();

    game.update(stepSeconds);

    if (const bool.fromEnvironment('TRACE_RESOURCES') &&
        step % (ShelterGame.secondsPerDay / stepSeconds).round() == 0) {
      // ignore: avoid_print
      print(
        'DAY ${day().toStringAsFixed(0)} '
        '⚡${resources.electricity.toStringAsFixed(1)} '
        '(+${resources.electricityProductionPerMinute.toStringAsFixed(2)} '
        '-${resources.electricityConsumptionPerMinute.toStringAsFixed(2)}) '
        '💧${resources.water.toStringAsFixed(1)} '
        '(+${resources.waterProductionPerMinute.toStringAsFixed(2)} '
        '-${resources.waterConsumptionPerMinute.toStringAsFixed(2)}) '
        '🍞${resources.food.toStringAsFixed(1)} '
        '(+${resources.foodProductionPerMinute.toStringAsFixed(2)} '
        '-${resources.foodConsumptionPerMinute.toStringAsFixed(2)})',
      );
    }

    if (traceDeaths) {
      for (final s in before) {
        if (!game.survivors.contains(s)) {
          // ignore: avoid_print
          print('DEATH day=${day().toStringAsFixed(2)} ${snapshot[s]}');
        }
      }
    }

    if (game.survivors.length < aliveBefore) result.firstDeathDay ??= day();
    if (resources.electricity <= 0) result.noPowerDay ??= day();
    if (resources.food < 0.5) result.noFoodDay ??= day();
    if (resources.water < 0.5) result.noWaterDay ??= day();

    if (game.isGameOver.value) {
      result.gameOverDay = day();
      break;
    }

    if (game.isVictory.value) {
      result.victory = true;
      break;
    }

    if (!active) continue;

    if (game.pendingVisitor.value != null && game.hasFreeBed) {
      if (game.acceptVisitor()) {
        result.acceptedVisitors++;
        _assignToNeediestRoom(game, game.survivors.last);

        // Yeni karakterin yüklenmesi (onLoad) tamamlansın.
        await tester.pump();
      }
    }

    if (step % decisionEvery != 0) continue;

    // Boşta kalanlar (ör. inşaatı biten inşaatçı) üretime döner.
    for (final survivor in game.survivors.toList()) {
      if (survivor.workRoomIndex == null) {
        _assignToNeediestRoom(game, survivor);
      }
    }

    if (_maybeBuildBedroom(game)) {
      // Yeni oda bileşeni inşaat bitince yüklenecek.
      result.builtRooms++;
    }

    // Biten inşaatın oda bileşeninin yüklenmesi.
    await tester.pump();
  }

  result.survivorsAtEnd = game.survivors.length;
  return result;
}

void main() {
  final results = <SimulationResult>[];

  for (final difficulty in Difficulty.values) {
    for (final active in [false, true]) {
      testWidgets(
        '${difficulty.settings.label} - ${active ? 'aktif' : 'pasif'} oyuncu',
        (tester) async {
          for (int seed = 1; seed <= runsPerScenario; seed++) {
            final result = await _simulate(
              tester,
              difficulty,
              seed,
              active: active,
            );
            results.add(result);

            // Simülasyon sonuna kadar ilerlemiş olmalı.
            expect(result.victory || result.gameOverDay != null, isTrue);
          }
        },
        timeout: const Timeout(Duration(minutes: 10)),
      );
    }
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('\n=== 30 GÜNLÜK SİMÜLASYON ===');
    for (final result in results) {
      // ignore: avoid_print
      print(result);
    }

    // ignore: avoid_print
    print('\n=== ÖZET (kazanılan / oynanan) ===');
    for (final difficulty in Difficulty.values) {
      for (final active in [false, true]) {
        final runs = results.where(
          (r) => r.difficulty == difficulty && r.active == active,
        );
        final wins = runs.where((r) => r.victory).length;

        // ignore: avoid_print
        print(
          '${difficulty.settings.label.padRight(7)}'
          '${(active ? 'aktif' : 'pasif').padRight(6)}'
          '$wins / ${runs.length}',
        );
      }
    }
  });
}
