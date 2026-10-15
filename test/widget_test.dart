
//import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';

import 'package:last_shelter/main.dart';

void main() {
  testWidgets('Last Shelter application starts', (tester) async {
    await tester.pumpWidget(const LastShelterApp());

    // Uygulama başlığı görüntüleniyor mu?
    expect(find.text('SON SIĞINAK'), findsOneWidget);

    // Flame oyun bileşeni oluşturulmuş mu?
    expect(find.byType(GameWidget), findsOneWidget);
  });
}
