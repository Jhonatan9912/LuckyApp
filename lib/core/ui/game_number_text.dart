// lib/core/ui/game_number_text.dart
//
// Número de juego listo para pintar. En Quinta se ve "1234-5" con el último
// dígito en rojo, igual que en las balotas. Lo usan la app y la web, del lado
// del cliente y del admin.
import 'package:flutter/material.dart';

import 'package:base_app/core/utils/lottery_number_format.dart';

/// Rojo del dígito extra de la Quinta.
const Color kQuintaRed = Color(0xFFE53935);

// Solo el formato exacto de Quinta, para no pintar de rojo otros textos con
// guion (códigos, fechas, teléfonos...).
final RegExp _quintaPattern = RegExp(r'^(\d{4}-)(\d)$');

/// Span con el número ya formateado (p. ej. "1234-5" o "045").
TextSpan gameNumberSpan(String text, {TextStyle? style}) {
  final m = _quintaPattern.firstMatch(text.trim());
  if (m == null) return TextSpan(text: text, style: style);
  return TextSpan(
    style: style,
    children: [
      TextSpan(text: m[1]),
      TextSpan(text: m[2], style: const TextStyle(color: kQuintaRed)),
    ],
  );
}

/// Varios números separados por [separator], cada uno con su formato.
/// Acepta enteros o texto con dígitos (como vienen guardados).
TextSpan gameNumbersSpan(
  Iterable<Object> numbers,
  int digits, {
  String separator = ', ',
  TextStyle? style,
}) {
  final children = <InlineSpan>[];
  for (final n in numbers) {
    if (children.isNotEmpty) children.add(TextSpan(text: separator));
    final value = n is int ? n : int.tryParse('$n'.trim());
    children.add(
      gameNumberSpan(value == null ? '$n' : formatGameNumber(value, digits)),
    );
  }
  return TextSpan(style: style, children: children);
}

class GameNumberText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// [text] ya formateado (p. ej. con [formatGameNumber]).
  const GameNumberText(this.text, {super.key, this.style, this.textAlign});

  GameNumberText.number(
    int number,
    int digits, {
    super.key,
    this.style,
    this.textAlign,
  }) : text = formatGameNumber(number, digits);

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      gameNumberSpan(text),
      style: style,
      textAlign: textAlign,
      maxLines: 1,
      softWrap: false,
    );
  }
}
