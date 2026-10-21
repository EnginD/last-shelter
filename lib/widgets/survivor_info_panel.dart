import 'package:flutter/material.dart';
import '../game/survivor.dart';
import '../game/shelter_game.dart';

class SurvivorInfoPanel extends StatelessWidget {
  final Survivor survivor;
  final String roomName;
  final VoidCallback onClose;
  final ShelterGame game;

  const SurvivorInfoPanel({
    super.key,
    required this.survivor,
    required this.roomName,
    required this.onClose,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    final isNeedActive = survivor.autoEating || survivor.autoDrinking;
    final isEating = survivor.autoEating;
    final efficiency = game.survivorEfficiency(survivor);

    final progress = survivor.needActionDuration > 0
        ? (survivor.needActionTimer / survivor.needActionDuration)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;

    final statusIcon = switch (survivor.state) {
      SurvivorState.walking => Icons.directions_walk,
      SurvivorState.working => Icons.handyman,
      SurvivorState.sleeping => Icons.bed,
      SurvivorState.waitingForBed => Icons.hourglass_empty,
      SurvivorState.idle => Icons.person_outline,
      SurvivorState.goingToEat => Icons.restaurant,
      SurvivorState.eating => Icons.restaurant,
      SurvivorState.goingToDrink => Icons.water_drop,
      SurvivorState.drinking => Icons.water_drop,
      SurvivorState.waitingForFood => Icons.hourglass_empty,
      SurvivorState.waitingForWater => Icons.hourglass_empty,
      SurvivorState.goingToMedical => Icons.local_hospital,
      SurvivorState.healing => Icons.healing,
    };

    final statusText = switch (survivor.state) {
      SurvivorState.walking => 'Walking',
      SurvivorState.working => 'Working',
      SurvivorState.sleeping => 'Sleeping',
      SurvivorState.waitingForBed => 'Waiting for bed',
      SurvivorState.idle => 'Idle',
      SurvivorState.goingToEat => 'Going to eat',
      SurvivorState.eating => 'Eating',
      SurvivorState.goingToDrink => 'Going to drink',
      SurvivorState.drinking => 'Drinking',
      SurvivorState.waitingForFood => 'Waiting for food',
      SurvivorState.waitingForWater => 'Waiting for water',
      SurvivorState.goingToMedical => 'Going to medical',
      SurvivorState.healing => 'Healing',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF252D34),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Survivor adı
            Row(
              children: [
                const Icon(Icons.person, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    survivor.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  iconSize: 20,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),

            const SizedBox(height: 4),

            _statusBar('Health', survivor.health, Colors.green),
            _statusBar('Hunger', survivor.hunger, Colors.orange),
            _statusBar('Thirst', survivor.thirst, Colors.blue),
            _statusBar('Energy', survivor.energy, Colors.amber),

            const Divider(color: Colors.white24, height: 10),

            _statusBar(
              'Efficiency',
              efficiency * 100,
              efficiency >= 0.90
                  ? Colors.green
                  : efficiency >= 0.75
                  ? Colors.orange
                  : Colors.red,
            ),

            // Yemek / su ilerleme göstergesi
            if (isNeedActive) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEating ? 'Eating' : 'Drinking',
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: Colors.white12,
                color: isEating ? Colors.orange : Colors.lightBlue,
              ),
              const SizedBox(height: 4),
              Text(
                survivor.isMoving
                    ? (isEating ? 'Moving to kitchen' : 'Moving to water room')
                    : survivor.needActionDuration > 0
                    ? '${survivor.needActionTimer.toStringAsFixed(1)} / '
                          '${survivor.needActionDuration.toStringAsFixed(1)} sec'
                    : 'Preparing...',
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ],

            const SizedBox(height: 8),

            // Skills - tek satır
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Skills:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Text(
                  '⚡ ${survivor.electricitySkill}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 10),
                Text(
                  '💧 ${survivor.waterSkill}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 10),
                Text(
                  '🍞 ${survivor.cookingSkill}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Oda ve durum - tek satır
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    roomName,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(statusIcon, size: 16),
                const SizedBox(width: 4),
                Text(statusText, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(String title, double value, Color color) {
    final double safeValue = value.clamp(0.0, 100.0).toDouble();

    // İhtiyaç seviyesine göre renk belirle.
    final Color statusColor;

    if (title == 'Efficiency') {
      // Efficiency kendi renk hesaplamasını kullanır.
      statusColor = color;
    } else if (safeValue < 25) {
      statusColor = Colors.red;
    } else if (safeValue < 50) {
      statusColor = Colors.deepOrange;
    } else {
      statusColor = color;
    }

    final bool isCritical = title != 'Efficiency' && safeValue < 25;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Row(
              children: [
                if (isCritical) ...[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      color: isCritical ? Colors.red : Colors.white,
                      fontWeight: isCritical
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: safeValue / 100,
              minHeight: 5,
              color: statusColor,
              backgroundColor: Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 35,
            child: Text(
              '${safeValue.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                color: isCritical ? Colors.red : Colors.white,
                fontWeight: isCritical ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
