// lib/web/screens/web_auth_layout.dart
//
// Estructura de las pantallas de acceso en web: presentación de la marca a la
// izquierda y el formulario en una tarjeta de vidrio a la derecha.
// En pantallas angostas se muestra solo el formulario con una cabecera compacta.
import 'package:flutter/material.dart';

import '../theme/web_palette.dart';
import '../theme/web_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/entrance.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_text.dart';
import '../widgets/lottery_ball.dart';

class WebAuthLayout extends StatelessWidget {
  final Widget form;
  final double formMaxWidth;

  const WebAuthLayout({super.key, required this.form, this.formMaxWidth = 460});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildWebTheme(),
      child: Scaffold(
        backgroundColor: WebPalette.bg,
        body: AuroraBackground(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1000;
              final card = ConstrainedBox(
                constraints: BoxConstraints(maxWidth: formMaxWidth),
                child: Entrance(
                  delay: const Duration(milliseconds: 250),
                  child: GlassCard(
                    glow: true,
                    padding: EdgeInsets.all(c.maxWidth < 480 ? 22 : 36),
                    child: form,
                  ),
                ),
              );

              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 28,
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const _Brand(),
                        const SizedBox(height: 28),
                        card,
                        const SizedBox(height: 24),
                        const _Footer(),
                      ],
                    ),
                  ),
                );
              }

              return Row(
                children: [
                  const Expanded(flex: 11, child: _Hero()),
                  Expanded(
                    flex: 9,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 40,
                        ),
                        child: card,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: WebPalette.gold.withValues(alpha: 0.35)),
          ),
          child: Image.asset('assets/icons/iconowithout.png'),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CM APP',
              style: WebPalette.display(19, weight: FontWeight.w800),
            ),
            Text(
              'Juega · Gana · Comparte',
              style: WebPalette.body(
                11.5,
                color: WebPalette.textFaint,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        return Stack(
          children: [
            // Balotas decorativas
            Positioned(
              right: 40,
              top: h * 0.12,
              child: const LotteryBall(number: '07', size: 92),
            ),
            Positioned(
              right: 150,
              top: h * 0.30,
              child: const LotteryBall(
                number: '23',
                size: 64,
                dark: true,
                floatPhase: 1.6,
              ),
            ),
            Positioned(
              right: 70,
              bottom: h * 0.16,
              child: const LotteryBall(number: '58', size: 76, floatPhase: 3.1),
            ),
            Positioned(
              right: 210,
              bottom: h * 0.06,
              child: const LotteryBall(
                number: '4',
                size: 48,
                dark: true,
                floatPhase: 4.4,
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(72, 48, 260, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Entrance(child: _Brand()),
                  const Spacer(),
                  Entrance(
                    delay: const Duration(milliseconds: 100),
                    child: _Pill(text: 'Ahora también en la web'),
                  ),
                  const SizedBox(height: 22),
                  Entrance(
                    delay: const Duration(milliseconds: 200),
                    child: Text(
                      'Tu suerte,',
                      style: WebPalette.display(64, weight: FontWeight.w800),
                    ),
                  ),
                  Entrance(
                    delay: const Duration(milliseconds: 280),
                    child: GradientText(
                      'en grande.',
                      style: WebPalette.display(64, weight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Entrance(
                    delay: const Duration(milliseconds: 360),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        'Elige tus números, sigue tus juegos en tiempo real y gana '
                        'con tus referidos. Todo desde tu computador, con la misma '
                        'cuenta de la app.',
                        style: WebPalette.body(17.5, height: 1.65),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  const Entrance(
                    delay: Duration(milliseconds: 460),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _Feature(
                          icon: Icons.casino_outlined,
                          title: 'Números al instante',
                        ),
                        _Feature(
                          icon: Icons.emoji_events_outlined,
                          title: 'Resultados claros',
                        ),
                        _Feature(
                          icon: Icons.groups_2_outlined,
                          title: 'Gana con referidos',
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Entrance(
                    delay: Duration(milliseconds: 560),
                    child: _Footer(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: WebPalette.gold.withValues(alpha: 0.10),
        border: Border.all(color: WebPalette.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: WebPalette.emerald,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            text,
            style: WebPalette.body(
              13,
              weight: FontWeight.w700,
              color: WebPalette.goldLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  const _Feature({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: WebPalette.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: WebPalette.goldGradient,
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF1A1300)),
          ),
          const SizedBox(width: 11),
          Text(
            title,
            style: WebPalette.body(
              14,
              weight: FontWeight.w600,
              color: WebPalette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 16,
          color: WebPalette.textFaint,
        ),
        const SizedBox(width: 8),
        Text(
          'Conexión segura · © ${DateTime.now().year} CM APP',
          style: WebPalette.body(12.5, color: WebPalette.textFaint),
        ),
      ],
    );
  }
}

/// Encabezado común de los formularios (título + subtítulo).
class WebFormHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const WebFormHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: WebPalette.display(30, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(subtitle, style: WebPalette.body(15)),
      ],
    );
  }
}
