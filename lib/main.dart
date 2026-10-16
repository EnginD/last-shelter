import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/shelter_game.dart';
import 'game/survivor.dart';
import 'widgets/survivor_info_panel.dart';
import 'models/survivor_candidate.dart';
import 'widgets/survivor_candidate_dialog.dart';
import 'game/room.dart';

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

    game.onRoomActionRequested = (survivor, roomIndex) {
      if (!mounted) return;

      showRoomActionDialog(survivor, roomIndex, game);
    };
  }

  @override
  void dispose() {
    game.selectedCharacter.dispose();
    game.deathNotification.dispose();
    game.isGameOver.dispose();

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
            left: 12,
            right: 160,
            child: ValueListenableBuilder<String?>(
              valueListenable: game.deathNotification,
              builder: (context, message, child) {
                if (message == null) {
                  return const SizedBox.shrink();
                }

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B1E1E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),

          Positioned(
            top: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ElevatedButton.icon(
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

                const SizedBox(height: 8),

                ElevatedButton(
                  onPressed: () {
                    game.resourceManager.setTestResources(food: 0, water: 0);
                  },
                  child: const Text('Test: Stok 0'),
                ),

                const SizedBox(height: 8),

                ElevatedButton(
                  onPressed: () {
                    game.resourceManager.setTestResources(
                      food: 100,
                      water: 100,
                    );
                  },
                  child: const Text('Test: Stok 100'),
                ),
              ],
            ),
          ),

          AnimatedBuilder(
            animation: Listenable.merge([
              game.selectedCharacter,
              game.uiRefresh,
            ]),
            builder: (context, child) {
              final survivor = game.selectedCharacter.value;

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

          ValueListenableBuilder<bool>(
            valueListenable: game.isGameOver,
            builder: (context, gameOver, child) {
              if (!gameOver) {
                return const SizedBox.shrink();
              }

              return Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.85),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.redAccent,
                          size: 80,
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          'SIĞINAK DÜŞTÜ!',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          'Sığınakta hayatta kalan kimse kalmadı.',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),

                        const SizedBox(height: 30),

                        ElevatedButton.icon(
                          onPressed: _restartGame,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Yeniden Başlat'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> showRoomActionDialog(
    Survivor survivor,
    int roomIndex,
    ShelterGame game,
  ) async {
    final room = game.rooms[roomIndex];

    final isKitchen = room.type == RoomType.kitchen;
    final isWater = room.type == RoomType.water;

    if (!isKitchen && !isWater) {
      return;
    }

    final action = await showDialog<SurvivorRoomAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isKitchen ? 'Yemekhane' : 'Su Arıtma'),
        content: const Text('Karakter bu odada ne yapsın?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, SurvivorRoomAction.work),
            child: const Text('Çalış'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              isKitchen ? SurvivorRoomAction.eat : SurvivorRoomAction.drink,
            ),
            child: Text(isKitchen ? 'Yemek Ye' : 'Su İç'),
          ),
        ],
      ),
    );

    if (!mounted || action == null) return;

    game.assignSurvivorToRoom(survivor, roomIndex, action);
  }

  void _restartGame() {
    final newGame = ShelterGame();

    newGame.onRoomActionRequested = (survivor, roomIndex) {
      if (!mounted) return;
      showRoomActionDialog(survivor, roomIndex, newGame);
    };

    setState(() {
      game = newGame;
    });

    // Eski oyun artık kullanılmıyor.
    // Flame'in yaşam döngüsü tamamlandıktan sonra
    // eski notifier'lar da temizlenebilir.
  }
}
