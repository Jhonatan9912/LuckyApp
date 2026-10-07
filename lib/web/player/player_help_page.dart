// lib/web/player/player_help_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:base_app/core/config/links.dart';

import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import '../widgets/web_ui.dart';

const _playSteps = [
  (
    'Pantalla inicial',
    'En "Juego actual" presiona JUGAR para generar tus 5 números.',
  ),
  (
    'Cambiar números',
    'Si no te gustan, usa "Volver a intentar" para generar otra combinación.',
  ),
  (
    'Reservar la jugada',
    'Al presionar RESERVAR las balotas aparecen una a una y la jugada queda a tu nombre.',
  ),
  ('Números reservados', 'Tus 5 números quedan fijos para ese juego.'),
  (
    'Ir al historial',
    'En Historial ves todos tus juegos; el recién reservado aparece "En juego".',
  ),
  (
    'Juego programado',
    'Cuando se programe el sorteo recibirás la lotería, la fecha y la hora.',
  ),
  (
    'Notificaciones',
    'Desde la campana también ves la información del juego programado.',
  ),
  (
    'Historial actualizado',
    'El juego muestra la lotería, fecha y hora configuradas.',
  ),
  (
    'Resultado publicado',
    'Cuando se publica el resultado recibes el número ganador.',
  ),
  (
    'Resultado "Perdido"',
    'Si el número ganador no está entre tus 5 números, el juego pasa a "Perdido".',
  ),
  (
    'Resultado "Ganado"',
    'Si alguno de tus números coincide, el juego pasa a "Ganado". ¡Felicidades!',
  ),
];

const _faqs = [
  (
    '¿Cómo funcionan los referidos?',
    'Al tener un plan pagado recibes un código único. Tus amigos lo escriben al registrarse y, cuando compran un plan, ganas una comisión.',
  ),
  (
    '¿Cuándo está disponible mi comisión?',
    'Cada comisión queda retenida 3 días para evitar fraudes o reembolsos. Después pasa a "Disponible".',
  ),
  (
    '¿Desde cuánto puedo retirar?',
    'Cuando acumules al menos \$100.000 COP disponibles se habilita el botón "Solicitar retiro".',
  ),
  (
    '¿Qué datos necesito para retirar?',
    'Para banco: banco, tipo y número de cuenta. Para billeteras (Nequi, Daviplata, etc.) solo el número de celular.',
  ),
  (
    '¿Qué pasa si rechazan mi retiro?',
    'Recibirás una notificación con el motivo y el dinero vuelve a "Disponible" para que corrijas los datos.',
  ),
  (
    '¿Cómo compro o renuevo mi plan?',
    'Desde la app de Android (Google Play) o escribiéndole a un asesor. El plan se activa en la web con la misma cuenta.',
  ),
  (
    'Olvidé mi contraseña',
    'En la pantalla de ingreso usa "¿Olvidaste tu contraseña?". Te enviaremos un código a tu correo para crear una nueva.',
  ),
];

class PlayerHelpPage extends StatelessWidget {
  const PlayerHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WebPage(
      children: [
        WebPanel(
          title: 'Cómo jugar paso a paso',
          subtitle:
              'Todo el recorrido desde que generas tus números hasta el resultado',
          icon: Icons.play_circle_outline_rounded,
          child: ResponsiveGrid(
            minItemWidth: 250,
            children: [
              for (var i = 0; i < _playSteps.length; i++)
                _StepCard(
                  index: i + 1,
                  title: _playSteps[i].$1,
                  text: _playSteps[i].$2,
                  image:
                      'assets/images/play/play_step_${(i + 1).toString().padLeft(2, '0')}.png',
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        WebPanel(
          title: 'Preguntas frecuentes',
          icon: Icons.quiz_outlined,
          child: Column(
            children: [for (final f in _faqs) _FaqTile(q: f.$1, a: f.$2)],
          ),
        ),
        const SizedBox(height: 22),
        WebPanel(
          highlight: true,
          icon: Icons.support_agent_rounded,
          title: '¿Necesitas ayuda personalizada?',
          subtitle: 'Escríbenos por WhatsApp y te respondemos.',
          actions: [
            GoldButton(
              label: 'Contactar soporte',
              expand: false,
              icon: Icons.arrow_forward_rounded,
              onPressed: () => launchUrl(
                Uri.parse(AppLinks.whatsappAdvisor),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final int index;
  final String title;
  final String text;
  final String image;
  const _StepCard({
    required this.index,
    required this.title,
    required this.text,
    required this.image,
  });

  void _zoom(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(image, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: WebPalette.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: GestureDetector(
              onTap: () => _zoom(context),
              child: Container(
                height: 200,
                color: Colors.black.withValues(alpha: 0.3),
                padding: const EdgeInsets.all(10),
                child: Image.asset(image, fit: BoxFit.contain),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PASO $index',
                  style: WebPalette.body(
                    11,
                    weight: FontWeight.w800,
                    color: WebPalette.goldLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: WebPalette.body(
                    15,
                    weight: FontWeight.w700,
                    color: WebPalette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(text, style: WebPalette.body(13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String q;
  final String a;
  const _FaqTile({required this.q, required this.a});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: _open ? 0.05 : 0.025),
        border: Border.all(
          color: _open
              ? WebPalette.gold.withValues(alpha: 0.35)
              : WebPalette.glassBorder,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.q,
                      style: WebPalette.body(
                        15,
                        weight: FontWeight.w700,
                        color: WebPalette.text,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: WebPalette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.a,
                        style: WebPalette.body(14, height: 1.6),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
