import 'package:flutter/material.dart';

import '../models/survivor_candidate.dart';

// Kapıya gelen ziyaretçi. Oyun durmaz; oyuncu süre dolmadan karar vermelidir.
class VisitorCard extends StatelessWidget {
  final SurvivorCandidate candidate;
  final int minutesLeft;
  final bool hasFreeBed;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const VisitorCard({
    super.key,
    required this.candidate,
    required this.minutesLeft,
    required this.hasFreeBed,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final carried = [
      if (candidate.food > 0) '🍞 ${candidate.food}',
      if (candidate.water > 0) '💧 ${candidate.water}',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2B3540),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.door_front_door, color: Colors.amber, size: 20),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Kapıda biri var!',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '⏳ $minutesLeft dk',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            '${candidate.name}, ${candidate.age}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 4),

          Text(
            '❤️ ${candidate.health}'
            '${candidate.isInjured ? ' (yaralı)' : ''}   '
            '⚡ ${candidate.electricitySkill}   '
            '💧 ${candidate.waterSkill}   '
            '🍞 ${candidate.cookingSkill}',
            style: TextStyle(
              fontSize: 12,
              color: candidate.isInjured ? Colors.redAccent : Colors.white,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            carried.isEmpty
                ? 'Yanında bir şey yok.'
                : 'Getirdikleri: ${carried.join('  ')}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              if (!hasFreeBed)
                const Expanded(
                  child: Text(
                    'Boş yatak yok',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                )
              else
                const Spacer(),
              TextButton(onPressed: onReject, child: const Text('Reddet')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: hasFreeBed ? onAccept : null,
                child: const Text('Kabul Et'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
