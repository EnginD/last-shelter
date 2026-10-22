import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/difficulty.dart';
import 'game/shelter_game.dart';
import 'game/survivor.dart';
import 'models/survivor_candidate.dart';
import 'widgets/survivor_info_panel.dart';
import 'widgets/visitor_card.dart';
import 'game/room.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Oyun dikey oynanır.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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
      home: const DifficultyScreen(),
    );
  }
}

// Oyun başlamadan önce zorluk seviyesi seçilir.
class DifficultyScreen extends StatelessWidget {
  const DifficultyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171B20),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield_moon, size: 72, color: Colors.amber),
              const SizedBox(height: 16),
              const Text(
                'LAST SHELTER',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sığınakta ${ShelterGame.targetDays} gün hayatta kal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 40),
              for (final difficulty in Difficulty.values) ...[
                _DifficultyButton(difficulty: difficulty),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultyButton extends StatelessWidget {
  final Difficulty difficulty;

  const _DifficultyButton({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final settings = difficulty.settings;

    final color = switch (difficulty) {
      Difficulty.easy => Colors.green,
      Difficulty.normal => Colors.amber,
      Difficulty.hard => Colors.redAccent,
    };

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.centerLeft,
      ),
      onPressed: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ShelterScreen(difficulty: difficulty),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settings.label,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            settings.description,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class ShelterScreen extends StatefulWidget {
  final Difficulty difficulty;

  const ShelterScreen({super.key, required this.difficulty});

  @override
  State<ShelterScreen> createState() => _ShelterScreenState();
}

class _ShelterScreenState extends State<ShelterScreen> {
  late ShelterGame game;

  @override
  void initState() {
    super.initState();

    game = _createGame();
  }

  // Oyunu oluşturur ve arayüz geri çağrılarını bağlar.
  ShelterGame _createGame() {
    final newGame = ShelterGame(difficulty: widget.difficulty);

    newGame.onRoomActionRequested = (survivor, roomIndex) {
      if (!mounted) return;

      showRoomActionDialog(survivor, roomIndex, newGame);
    };

    newGame.onBuildRequested = (survivor, roomIndex) {
      if (!mounted) return;

      showBuildDialog(survivor, roomIndex, newGame);
    };

    newGame.onMessage = (message) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    };

    return newGame;
  }

  @override
  void dispose() {
    game.selectedCharacter.dispose();
    game.deathNotification.dispose();
    game.isGameOver.dispose();
    game.isVictory.dispose();
    game.pendingVisitor.dispose();

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
        title: Text('LAST SHELTER · ${widget.difficulty.settings.label}'),
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

          // Bildirimler: kaynak satırının altında, ekran genişliğinde.
          Positioned(
            top: 100,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDeathNotification(),
                _buildVisitorCard(),
              ],
            ),
          ),

          // Test butonları sadece geliştirme sırasında görünür.
          if (kDebugMode)
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                  game: game,
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

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: _backToMenu,
                          child: const Text('Zorluk Seç'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: game.isVictory,
            builder: (context, victory, child) {
              if (!victory) {
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
                          Icons.emoji_events,
                          color: Colors.amber,
                          size: 80,
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          'HAYATTA KALDINIZ!',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          '${ShelterGame.targetDays} gün boyunca sığınak ayakta kaldı.\n'
                          'Hayatta kalan: ${game.survivors.length} kişi',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 30),

                        ElevatedButton.icon(
                          onPressed: _restartGame,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Yeniden Başlat'),
                        ),

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: _backToMenu,
                          child: const Text('Zorluk Seç'),
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

  Widget _buildDeathNotification() {
    return ValueListenableBuilder<String?>(
      valueListenable: game.deathNotification,
      builder: (context, message, child) {
        if (message == null) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    );
  }

  Widget _buildVisitorCard() {
    // Kalan süre 0,5 saniyede bir güncellenir.
    return AnimatedBuilder(
      animation: Listenable.merge([game.pendingVisitor, game.uiRefresh]),
      builder: (context, child) {
        final SurvivorCandidate? candidate = game.pendingVisitor.value;

        if (candidate == null) {
          return const SizedBox.shrink();
        }

        return VisitorCard(
          candidate: candidate,
          minutesLeft: game.visitorMinutesLeft,
          hasFreeBed: game.hasFreeBed,
          onReject: game.rejectVisitor,
          onAccept: () {
            final success = game.acceptVisitor();

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? '${candidate.name} sığınağa katıldı.'
                      : 'Sığınakta boş yatak yok.',
                ),
              ),
            );
          },
        );
      },
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

  Future<void> showBuildDialog(
    Survivor? survivor,
    int roomIndex,
    ShelterGame game,
  ) async {
    final room = game.rooms[roomIndex];
    final construction = room.construction;

    // Devam eden inşaat: katıl veya iptal et.
    if (construction != null) {
      final refund =
          game.buildCost(construction) * ShelterGame.constructionRefundRatio;

      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('🚧 ${ShelterRoom.nameOf(construction.type)} inşaatı'),
          content: Text(
            'İlerleme: %${(room.constructionProgress * 100).floor()}\n\n'
            '${survivor == null ? 'İnşaata katılması için önce bir karakter seçin.' : '${survivor.name} inşaata katılsın mı?'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: Text('İptal Et (+${refund.floor()} ⚡)'),
            ),
            if (survivor != null)
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'join'),
                child: const Text('Katıl'),
              ),
          ],
        ),
      );

      if (!mounted) return;

      if (choice == 'join' && survivor != null) {
        game.joinConstruction(roomIndex, survivor);
      } else if (choice == 'cancel') {
        game.cancelConstruction(roomIndex);
      }

      return;
    }

    // Boş alan: inşa edilecek odayı seç.
    final option = await showModalBottomSheet<BuildOption>(
      context: context,
      backgroundColor: const Color(0xFF252D34),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                survivor == null
                    ? 'Ne inşa edilsin?\n(İnşaatçı yok — sonra karakter atayın)'
                    : 'Ne inşa edilsin? İnşaatçı: ${survivor.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final option in ShelterRoom.buildOptions)
              ListTile(
                enabled: game.canAffordBuild(option),
                leading: Text(
                  ShelterRoom.iconOf(option.type),
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(ShelterRoom.nameOf(option.type)),
                subtitle: Text(_buildBenefit(option.type)),
                trailing: Text(
                  '${game.buildCost(option).floor()} ⚡\n'
                  '${option.buildHours.floor()} saat',
                  textAlign: TextAlign.right,
                ),
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
      ),
    );

    if (!mounted || option == null) return;

    game.startConstruction(roomIndex, option, survivor);
  }

  String _buildBenefit(RoomType type) => switch (type) {
    RoomType.bedroom => '+4 yatak (nüfus sınırı)',
    RoomType.kitchen => '+3 aşçı yeri',
    RoomType.water => '+3 işçi yeri',
    RoomType.power => '+3 işçi yeri',
    RoomType.medical => '+2 sedye',
    _ => '',
  };

  void _backToMenu() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DifficultyScreen()),
    );
  }

  void _restartGame() {
    final newGame = _createGame();

    setState(() {
      game = newGame;
    });

    // Eski oyun artık kullanılmıyor.
    // Flame'in yaşam döngüsü tamamlandıktan sonra
    // eski notifier'lar da temizlenebilir.
  }
}
