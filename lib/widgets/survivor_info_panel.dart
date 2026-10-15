import 'package:flutter/material.dart';
import '../game/survivor.dart';

class SurvivorInfoPanel extends StatelessWidget {
  final Survivor survivor;
  final String roomName;
  final VoidCallback onClose;

  const SurvivorInfoPanel({
    super.key,
    required this.survivor,
    required this.roomName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF252D34),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.person, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    survivor.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
              ],
            ),
            _statusBar('Health', survivor.health, Colors.green),
            _statusBar('Hunger', survivor.hunger, Colors.orange),
            _statusBar('Thirst', survivor.thirst, Colors.blue),
            _statusBar('Energy', survivor.energy, Colors.amber),
            const SizedBox(height: 12),

            const SizedBox(height: 12),

            const Text(
              'Skills',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text('⚡ Electricity: ${survivor.electricitySkill}'),
            Text('💧 Water: ${survivor.waterSkill}'),
            Text('🍞 Cooking: ${survivor.cookingSkill}'),
            Row(
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text('Assigned room: $roomName')),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(switch (survivor.state) {
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
                }),
                Text(switch (survivor.state) {
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
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(String title, double value, Color color) {
    final safeValue = value.clamp(0.0, 100.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 65, child: Text(title)),
          Expanded(
            child: LinearProgressIndicator(
              value: safeValue / 100,
              minHeight: 9,
              color: color,
              backgroundColor: Colors.white12,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 40, child: Text('${safeValue.toStringAsFixed(0)}%')),
        ],
      ),
    );
  }
}
