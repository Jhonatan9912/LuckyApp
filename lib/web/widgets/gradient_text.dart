// lib/web/widgets/gradient_text.dart
import 'package:flutter/material.dart';

import '../theme/web_palette.dart';

/// Texto con relleno degradado dorado.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;
  final TextAlign? textAlign;

  const GradientText(
    this.text, {
    super.key,
    required this.style,
    this.gradient = WebPalette.goldTextGradient,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => gradient.createShader(Offset.zero & r.size),
      child: Text(text, style: style, textAlign: textAlign),
    );
  }
}
