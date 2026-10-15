import 'package:flutter/material.dart';
import '../models/survivor_candidate.dart';

class SurvivorCandidateDialog extends StatelessWidget {
  final SurvivorCandidate candidate;

  const SurvivorCandidateDialog({super.key, required this.candidate});

  Widget _skillRow(String title, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title: $value'),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: value / 100, minHeight: 7),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni Hayatta Kalan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Icon(Icons.person, size: 64)),
            const SizedBox(height: 12),
            Text(
              candidate.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text('Yaş: ${candidate.age}'),
            const SizedBox(height: 12),
            _skillRow('Sağlık', candidate.health),
            _skillRow('Elektrik', candidate.electricitySkill),
            _skillRow('Su', candidate.waterSkill),
            _skillRow('Yemek', candidate.cookingSkill),
            const SizedBox(height: 12),
            const Text(
              'Bu kişiyi sığınağa kabul etmek '
              'istiyor musunuz?',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context, false);
          },
          child: const Text('Reddet'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, true);
          },
          child: const Text('Kabul Et'),
        ),
      ],
    );
  }
}
