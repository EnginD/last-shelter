import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_shelter/game/shelter_game.dart';
import 'package:last_shelter/main.dart';

void main() {
  testWidgets('Uygulama zorluk seçimiyle açılır ve oyunu başlatır', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(const LastShelterApp());

    // Açılış ekranı ve üç zorluk seviyesi görünüyor mu?
    expect(find.text('LAST SHELTER'), findsOneWidget);
    expect(find.text('Kolay'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Zor'), findsOneWidget);

    await tester.tap(find.text('Normal'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Flame oyun bileşeni seçilen zorlukla oluşturulmuş mu?
    expect(find.byType(GameWidget<ShelterGame>), findsOneWidget);
    expect(find.text('LAST SHELTER · Normal'), findsOneWidget);
  });
}
