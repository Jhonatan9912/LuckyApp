import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:base_app/core/ui/game_number_text.dart';
import 'package:base_app/web/widgets/lottery_ball.dart';

/// Texto plano y color de cada tramo del span.
List<(String, Color?)> _parts(TextSpan span) {
  final out = <(String, Color?)>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) out.add((s.text!, s.style?.color));
    return true;
  });
  return out;
}

void main() {
  test('Quinta se ve 1234-5 con el último dígito en rojo', () {
    final span = gameNumberSpan('1234-5');
    expect(span.toPlainText(), '1234-5');
    expect(_parts(span).last, ('5', kQuintaRed));
  });

  test('otros textos con guion no se pintan de rojo', () {
    for (final t in ['045', '0123', 'PB-000001', '2026-10-16', '300-123']) {
      final span = gameNumberSpan(t);
      expect(span.toPlainText(), t);
      expect(_parts(span).any((p) => p.$2 == kQuintaRed), isFalse, reason: t);
    }
  });

  test('lista de números guardados (int o texto) se formatea', () {
    final span = gameNumbersSpan(const [12345, '00071', 9], 5);
    expect(span.toPlainText(), '1234-5, 0007-1, 0000-9');
    final reds = _parts(span).where((p) => p.$2 == kQuintaRed).map((p) => p.$1);
    expect(reds, ['5', '1', '9']);
  });

  test('3 y 4 cifras quedan igual', () {
    expect(gameNumbersSpan(const [7, 45], 3).toPlainText(), '007, 045');
    expect(GameNumberText.number(12, 4).text, '0012');
  });

  testWidgets('balota web muestra el guion de la Quinta', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: BallNumberText('1234-5', style: TextStyle(fontSize: 14)),
      ),
    );
    final rich = t.widget<Text>(find.byType(Text).first).textSpan!;
    expect(rich.toPlainText(), '1234-5');
  });
}
