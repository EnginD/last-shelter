import 'package:flutter/foundation.dart';

class ResourceManager extends ChangeNotifier {
  double electricity = 100;
  double water = 100;
  double food = 100;

  final double maxResource = 200;

  int population = 3;
  int maxPopulation = 12;

  double electricityWorkers = 0;
  double waterWorkers = 0;
  double foodWorkers = 0;

  double electricityProductionPerMinute = 0;
  double waterProductionPerMinute = 0;
  double foodProductionPerMinute = 0;

  // Saniyelik üretim değerleri
  double get electricityProduction => electricityWorkers * 6 / 60;
  double get waterProduction => waterWorkers * 5 / 60;
  double get foodProduction => foodWorkers * 4 / 60;

  // Saniyelik tüketim değerleri
  double get electricityConsumption => 3 / 60;
  double get waterConsumption => population / 60;
  double get foodConsumption => population / 60;

  double get electricityNetPerMinute => electricityProductionPerMinute - 3.0;

  double get waterNetPerMinute => waterProductionPerMinute;

  double get foodNetPerMinute => foodProductionPerMinute;

  void updateResources(double dt) {
    final minutes = dt / 60.0;

    electricity =
        (electricity + (electricityProductionPerMinute - 3.0) * minutes).clamp(
          0.0,
          maxResource,
        );

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

  void updateWorkers({
    required int electricity,
    required int water,
    required int food,
  }) {
    electricityWorkers = electricity.toDouble();
    waterWorkers = water.toDouble();
    foodWorkers = food.toDouble();

    notifyListeners();
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
}
