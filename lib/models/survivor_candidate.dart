import 'dart:math';

class SurvivorCandidate {
  final String name;
  final int age;
  final int health;
  final int electricitySkill;
  final int waterSkill;
  final int cookingSkill;

  // Ziyaretçinin yanında getirdiği kaynaklar.
  final int food;
  final int water;

  const SurvivorCandidate({
    required this.name,
    required this.age,
    required this.health,
    required this.electricitySkill,
    required this.waterSkill,
    required this.cookingSkill,
    this.food = 0,
    this.water = 0,
  });

  bool get isInjured => health < 50;

  static final Random _random = Random();

  static const List<String> _names = [
    'Deniz Yılmaz',
    'Ece Demir',
    'Mert Kaya',
    'Zeynep Arslan',
    'Can Aydın',
    'Elif Çelik',
    'Burak Şahin',
    'Selin Koç',
  ];

  // Yaralı gelme ve yanında yemek/su getirme ihtimalleri
  // zorluk seviyesine göre verilir.
  factory SurvivorCandidate.random({
    double injuredChance = 0.25,
    double carryChance = 0.4,
    Random? random,
  }) {
    final r = random ?? _random;
    final injured = r.nextDouble() < injuredChance;

    final food = r.nextDouble() < carryChance ? 2 + r.nextInt(7) : 0;
    final water = r.nextDouble() < carryChance ? 2 + r.nextInt(7) : 0;

    return SurvivorCandidate(
      name: _names[r.nextInt(_names.length)],
      age: 18 + r.nextInt(43),
      health: injured ? 20 + r.nextInt(26) : 60 + r.nextInt(41),
      electricitySkill: 10 + r.nextInt(91),
      waterSkill: 10 + r.nextInt(91),
      cookingSkill: 10 + r.nextInt(91),
      food: food,
      water: water,
    );
  }
}
