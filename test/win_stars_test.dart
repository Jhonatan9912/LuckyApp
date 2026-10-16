import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:base_app/presentation/widgets/wins/win_stars.dart';

void main() {
  test('niveles de ganador', () {
    expect(WinTier.of(0), isNull);
    expect(WinTier.of(1), WinTier.bronze);
    expect(WinTier.of(5), WinTier.silver);
    expect(WinTier.of(19), WinTier.gold);
    expect(WinTier.of(20), WinTier.diamond);
    expect(WinTier.next(7), WinTier.gold);
    expect(WinTier.next(50), isNull);
  });

  Future<void> pump(WidgetTester t, int wins, {bool showEmpty = false}) =>
      t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: WinStarsBadge(wins: wins, showEmpty: showEmpty),
            ),
          ),
        ),
      );

  testWidgets('sin victorias no ocupa espacio en listas', (t) async {
    await pump(t, 0);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
  });

  testWidgets('el jugador ve una estrella apagada', (t) async {
    await pump(t, 0, showEmpty: true);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
  });

  testWidgets('pocas victorias: estrellas sueltas', (t) async {
    await pump(t, 2);
    await t.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
  });

  testWidgets('muchas victorias se agrupan en una estrella', (t) async {
    for (final wins in [7, 25, 120]) {
      await pump(t, wins);
      await t.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.text('×$wins'), findsOneWidget);
    }
  });

  testWidgets('el detalle abre y muestra el nivel', (t) async {
    await pump(t, 12);
    await t.tap(find.byType(WinStarsBadge));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('¡Has ganado 12 veces!'), findsOneWidget);
    expect(find.text('Nivel Oro'), findsOneWidget);
    expect(find.text('Faltan 8 victorias para Diamante'), findsOneWidget);
  });
}
