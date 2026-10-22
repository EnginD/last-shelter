import 'package:flutter/foundation.dart';

import 'difficulty.dart';
import 'survivor.dart';

class ResourceManager extends ChangeNotifier {
  final DifficultySettings settings;

  late double electricity = settings.startingResources;
  late double water = settings.startingResources;
  late double food = settings.startingResources;

  final double maxResource = 200;

  int population = 3;

  ResourceManager(this.settings);

  // Tam bir öğün (açlık 0 → 100) ve tam bir içiş (susuzluk 0 → 100)
  // için harcanan kaynak miktarı. Kısmi ihtiyaç orantılı harcar.
  double get foodPerFullMeal => 1.35 * settings.consumptionMultiplier;
  double get waterPerFullDrink => 1.35 * settings.consumptionMultiplier;

  // Elektrik tüketimi: sığınağın sabit yükü + kişi başı yük (dakikada).
  static const double baseElectricityPerMinute = 1.5;
  static const double electricityPerPersonPerMinute = 0.25;

  // Sonradan inşa edilen her oda kalıcı ek elektrik yükü getirir.
  static const double electricityPerBuiltRoomPerMinute = 0.2;
  int builtRooms = 0;

  // Elektrik yokken su arıtma hiç çalışmaz; mutfak ve revir yarı hızdadır.
  static const double noPowerWaterMultiplier = 0.0;
  static const double noPowerMultiplier = 0.5;

  double electricityProductionPerMinute = 0;
  double waterProductionPerMinute = 0;
  double foodProductionPerMinute = 0;

  bool get hasPower => electricity > 0;

  double get powerMultiplier => hasPower ? 1.0 : noPowerMultiplier;

  double get waterPowerMultiplier => hasPower ? 1.0 : noPowerWaterMultiplier;

  double get electricityConsumptionPerMinute =>
      (baseElectricityPerMinute +
          population * electricityPerPersonPerMinute +
          builtRooms * electricityPerBuiltRoomPerMinute) *
      settings.consumptionMultiplier;

  // Nüfusun ortalama yemek/su tüketimi (dakikada, tahmini).
  double get foodConsumptionPerMinute =>
      population * Survivor.hungerLossPerMinute / 100 * foodPerFullMeal;

  double get waterConsumptionPerMinute =>
      population * Survivor.thirstLossPerMinute / 100 * waterPerFullDrink;

  double get electricityNetPerMinute =>
      electricityProductionPerMinute - electricityConsumptionPerMinute;

  double get waterNetPerMinute =>
      waterProductionPerMinute - waterConsumptionPerMinute;

  double get foodNetPerMinute =>
      foodProductionPerMinute - foodConsumptionPerMinute;

  void updateResources(double dt) {
    final minutes = dt / 60.0;

    electricity = (electricity + electricityNetPerMinute * minutes).clamp(
      0.0,
      maxResource,
    );

    // Yemek ve su, karakterler yerken/içerken harcanır.
    water = (water + waterProductionPerMinute * minutes).clamp(
      0.0,
      maxResource,
    );

    food = (food + foodProductionPerMinute * minutes).clamp(0.0, maxResource);

    notifyListeners();
  }

  void updateProduction({
    required double electricity,
    required double water,
    required double food,
  }) {
    electricityProductionPerMinute = electricity;
    waterProductionPerMinute = water;
    foodProductionPerMinute = food;
  }

  bool consumeFood(double amount) {
    if (food < amount) return false;

    food = (food - amount).clamp(0.0, maxResource);
    notifyListeners();
    return true;
  }

  bool consumeWater(double amount) {
    if (water < amount) return false;

    water = (water - amount).clamp(0.0, maxResource);
    notifyListeners();
    return true;
  }

  bool consumeElectricity(double amount) {
    if (electricity < amount) return false;

    electricity = (electricity - amount).clamp(0.0, maxResource);
    notifyListeners();
    return true;
  }

  void addElectricity(double amount) {
    electricity = (electricity + amount).clamp(0.0, maxResource);
    notifyListeners();
  }

  // Depoya kaynak ekle (rezervasyon iadesi veya ziyaretçinin getirdikleri).
  void addFood(double amount) {
    food = (food + amount).clamp(0.0, maxResource);
    notifyListeners();
  }

  void addWater(double amount) {
    water = (water + amount).clamp(0.0, maxResource);
    notifyListeners();
  }

  void setTestResources({double? food, double? water}) {
    if (food != null) {
      this.food = food.clamp(0.0, maxResource).toDouble();
    }

    if (water != null) {
      this.water = water.clamp(0.0, maxResource).toDouble();
    }

    notifyListeners();
  }
}
