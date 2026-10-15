import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/shelter_game.dart';
import 'game/survivor.dart';
import 'widgets/survivor_info_panel.dart';
import 'models/survivor_candidate.dart';
import 'widgets/survivor_candidate_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LastShelterApp());
}

class LastShelterApp extends StatelessWidget {
  const LastShelterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Last Shelter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const ShelterScreen(),
    );
  }
}

class ShelterScreen extends StatefulWidget {
  const ShelterScreen({super.key});

  @override
  State<ShelterScreen> createState() => _ShelterScreenState();
}

class _ShelterScreenState extends State<ShelterScreen> {
  late final ShelterGame game;

  @override
  void initState() {
    super.initState();
    game = ShelterGame();
  }

  @override
  void dispose() {
    game.selectedCharacter.dispose();
    super.dispose();
  }

  String _getRoomName(Survivor survivor) {
    final index = survivor.assignedRoomIndex;

    if (index == null || index < 0 || index >= game.rooms.length) {
      return 'Unassigned';
    }

    return game.rooms[index].roomName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAST SHELTER'),
        backgroundColor: const Color(0xFF20252B),
      ),

      body: Stack(
        fit: StackFit.expand,
        children: [
          GameWidget(
            game: game,
            loadingBuilder: (context) {
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Game error:\n$error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 12,
            right: 12,
            child: ElevatedButton.icon(
              onPressed: () async {
                final candidate = SurvivorCandidate.random();

                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) {
                    return SurvivorCandidateDialog(candidate: candidate);
                  },
                );

                if (!mounted) return;

                if (accepted != true) return;

                final success = game.addNewSurvivor(candidate);

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? '${candidate.name} sığınağa katıldı.'
                          : 'Sığınakta boş yatak veya nüfus kapasitesi yok.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('+ Survivor'),
            ),
          ),
          ValueListenableBuilder<Survivor?>(
            valueListenable: game.selectedCharacter,
            builder: (context, survivor, child) {
              if (survivor == null) {
                return const SizedBox.shrink();
              }

              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SurvivorInfoPanel(
                  survivor: survivor,
                  roomName: _getRoomName(survivor),
                  onClose: () {
                    game.selectedCharacter.value = null;
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
