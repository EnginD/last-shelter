import 'dart:math';

class SurvivorCandidate {
  final String name;
  final int age;
  final int health;
  final int electricitySkill;
  final int waterSkill;
  final int cookingSkill;

  const SurvivorCandidate({
    required this.name,
    required this.age,
    required this.health,
    required this.electricitySkill,
    required this.waterSkill,
    required this.cookingSkill,
  });

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

  factory SurvivorCandidate.random() {
    return SurvivorCandidate(
      name: _names[_random.nextInt(_names.length)],
      age: 18 + _random.nextInt(43),
      health: 50 + _random.nextInt(51),
      electricitySkill: 10 + _random.nextInt(91),
      waterSkill: 10 + _random.nextInt(91),
      cookingSkill: 10 + _random.nextInt(91),
    );
  }
}
