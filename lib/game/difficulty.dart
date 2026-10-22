import 'dart:math';

enum Difficulty { easy, normal, hard }

// Başlangıç karakterlerinin uzmanlık dağılımı.
enum StarterSpecialties {
  // Herkes farklı bir alanda usta: doğru yerleştirme açıktır.
  distinct,

  // Uzmanlıklar rastgele: iki kişi aynı alanda usta olabilir.
  random,

  // İki kişi aynı alanda usta, bir alanda hiç usta yok: taviz gerekir.
  overlapping,
}

// Başlangıç karakterinin becerileri.
class StarterProfile {
  final int electricitySkill;
  final int waterSkill;
  final int cookingSkill;
  final int health;

  const StarterProfile({
    required this.electricitySkill,
    required this.waterSkill,
    required this.cookingSkill,
    required this.health,
  });
}

// Zorluk seviyesine göre oyun ayarları. Normal = 1.0 temel değerlerdir.
class DifficultySettings {
  final String label;
  final String description;

  // Başlangıçtaki elektrik, su ve yemek miktarı.
  final double startingResources;

  // Elektrik, su ve yemek üretim çarpanı.
  final double productionMultiplier;

  // Yemek, su ve elektrik tüketim çarpanı.
  final double consumptionMultiplier;

  // Açlık/susuzluk sıfırken alınan sağlık hasarı çarpanı.
  final double starvationDamageMultiplier;

  // İnşaat elektrik maliyeti çarpanı.
  final double buildCostMultiplier;

  // İki ziyaretçi arasındaki süre (gün).
  final double visitorMinDays;
  final double visitorMaxDays;

  final double visitorInjuredChance;
  final double visitorCarryChance;

  // Ziyaretçiye karar verme süresi (oyun dakikası).
  final double visitorResponseMinutes;

  // BAŞLANGIÇ KARAKTERLERİ
  final StarterSpecialties starterSpecialties;

  // Uzman olunan alandaki beceri aralığı.
  final int specialtyMin;
  final int specialtyMax;

  // Diğer alanlardaki beceri aralığı.
  final int otherSkillMin;
  final int otherSkillMax;

  // Bir karakter hafif yaralı başlar mı?
  final bool oneStarterInjured;

  const DifficultySettings({
    required this.label,
    required this.description,
    required this.startingResources,
    required this.productionMultiplier,
    required this.consumptionMultiplier,
    required this.starvationDamageMultiplier,
    required this.buildCostMultiplier,
    required this.visitorMinDays,
    required this.visitorMaxDays,
    required this.visitorInjuredChance,
    required this.visitorCarryChance,
    required this.visitorResponseMinutes,
    required this.starterSpecialties,
    required this.specialtyMin,
    required this.specialtyMax,
    required this.otherSkillMin,
    required this.otherSkillMax,
    required this.oneStarterInjured,
  });

  int _between(Random random, int min, int max) =>
      min + random.nextInt(max - min + 1);

  // Başlangıç karakterlerinin becerilerini zorluğa göre rastgele üretir.
  // Alanlar: 0 = elektrik, 1 = su, 2 = yemek.
  List<StarterProfile> generateStarters(Random random, int count) {
    final List<int> specialties;

    switch (starterSpecialties) {
      case StarterSpecialties.distinct:
        specialties = [0, 1, 2]..shuffle(random);

      case StarterSpecialties.random:
        specialties = [for (int i = 0; i < count; i++) random.nextInt(3)];

      case StarterSpecialties.overlapping:
        final areas = [0, 1, 2]..shuffle(random);
        // areas[0]: iki usta, areas[1]: bir usta, areas[2]: usta yok.
        specialties = [areas[0], areas[0], areas[1]]..shuffle(random);
    }

    final injured = oneStarterInjured ? random.nextInt(count) : -1;

    return [
      for (int i = 0; i < count; i++)
        () {
          final specialty = specialties[i % specialties.length];

          int skill(int area) => area == specialty
              ? _between(random, specialtyMin, specialtyMax)
              : _between(random, otherSkillMin, otherSkillMax);

          return StarterProfile(
            electricitySkill: skill(0),
            waterSkill: skill(1),
            cookingSkill: skill(2),
            health: i == injured ? _between(random, 40, 60) : 100,
          );
        }(),
    ];
  }
}

extension DifficultyX on Difficulty {
  DifficultySettings get settings => switch (this) {
    Difficulty.easy => const DifficultySettings(
      label: 'Kolay',
      description: 'Bol kaynak, herkes farklı bir işte usta, sık ziyaretçiler.',
      startingResources: 150,
      productionMultiplier: 1.1,
      consumptionMultiplier: 0.9,
      starvationDamageMultiplier: 0.75,
      buildCostMultiplier: 0.75,
      visitorMinDays: 0.75,
      visitorMaxDays: 1.5,
      visitorInjuredChance: 0.15,
      visitorCarryChance: 0.5,
      visitorResponseMinutes: 90,
      starterSpecialties: StarterSpecialties.distinct,
      specialtyMin: 70,
      specialtyMax: 90,
      otherSkillMin: 30,
      otherSkillMax: 50,
      oneStarterInjured: false,
    ),
    Difficulty.normal => const DifficultySettings(
      label: 'Normal',
      description: 'Dengeli kaynaklar, rastgele yetenekler. Her karar önemli.',
      startingResources: 100,
      productionMultiplier: 1.0,
      consumptionMultiplier: 1.0,
      starvationDamageMultiplier: 1.0,
      buildCostMultiplier: 1.0,
      visitorMinDays: 1,
      visitorMaxDays: 2,
      visitorInjuredChance: 0.25,
      visitorCarryChance: 0.4,
      visitorResponseMinutes: 60,
      starterSpecialties: StarterSpecialties.random,
      specialtyMin: 60,
      specialtyMax: 85,
      otherSkillMin: 20,
      otherSkillMax: 50,
      oneStarterInjured: false,
    ),
    Difficulty.hard => const DifficultySettings(
      label: 'Zor',
      description:
          'Az kaynak, bir alanda hiç usta yok, nadir ve çoğu yaralı ziyaretçiler.',
      startingResources: 80,
      productionMultiplier: 0.95,
      consumptionMultiplier: 1.0,
      starvationDamageMultiplier: 1.25,
      buildCostMultiplier: 1.25,
      visitorMinDays: 1.5,
      visitorMaxDays: 3,
      visitorInjuredChance: 0.4,
      visitorCarryChance: 0.25,
      visitorResponseMinutes: 40,
      starterSpecialties: StarterSpecialties.overlapping,
      specialtyMin: 70,
      specialtyMax: 90,
      otherSkillMin: 10,
      otherSkillMax: 40,
      oneStarterInjured: true,
    ),
  };
}
