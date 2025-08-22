// lib/presentation/screens/faq/faq_play_screen.dart
import 'package:flutter/material.dart';

class FaqPlayScreen extends StatelessWidget {
  const FaqPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ⚠️ Coloca tus 12 imágenes en: assets/images/play/
    // Nómbralas así (o cambia abajo los nombres):
    // play_01.png ... play_12.png
    final steps = <_PlayStep>[
      _PlayStep(
        title: '1) Pantalla inicial: botón “JUGAR”',
        desc:
            'En “Juego actual” verás la interfaz de juego en limpio con el botón “JUGAR”. '
            'Desde aquí puedes iniciar una jugada cuando esté habilitado.',
        img: 'assets/images/play/play_step_01.png',
      ),
      _PlayStep(
        title: '2) Cambiar números (volver a intentar)',
        desc:
            'Si quieres cambiar tu selección, toca el botón inferior de “volver a intentar / recargar”. '
            'Esto genera otra combinación de números.',
        img: 'assets/images/play/play_step_02.png',
      ),
      _PlayStep(
        title: '3) Reservar la jugada',
        desc:
            'Cuando presionas “RESERVAR”, las balotas aparecen dinámicamente una a una y '
            'la jugada queda guardada a tu nombre. Después de reservar, ya no puedes cambiar los números.',
        img: 'assets/images/play/play_step_03.png',
      ),
      _PlayStep(
        title: '4) Números reservados',
        desc:
            'Aquí ves los 5 números de 3 dígitos que reservaste. Ya están fijos para el juego.',
        img: 'assets/images/play/play_step_04.png',
      ),
      _PlayStep(
        title: '5) Ir al “Historial”',
        desc:
            'En la pestaña “Historial” encontrarás todos los juegos que has jugado. '
            'El juego recién reservado aparece con estado “En juego”.',
        img: 'assets/images/play/play_step_05.png',
      ),
      _PlayStep(
        title: '6) Notificación con lotería, fecha y hora',
        desc:
            'Cuando el administrador programe el juego, recibirás una notificación con la lotería, '
            'la fecha y la hora en que se jugará.',
        img: 'assets/images/play/play_step_06.png',
      ),
      _PlayStep(
        title: '7) Campana de notificaciones',
        desc:
            'Desde el ícono de la campana también puedes ver la información del juego programado.',
        img: 'assets/images/play/play_step_07.png',
      ),
      _PlayStep(
        title: '8) Historial actualizado con programación',
        desc:
            'En “Historial”, el juego muestra los datos de lotería, fecha y hora configurados por el administrador.',
        img: 'assets/images/play/play_step_08.png',
      ),
      _PlayStep(
        title: '9) Notificación de resultado (hay ganador)',
        desc:
            'Cuando llega la fecha y hora del sorteo y el administrador publica el resultado, '
            'recibirás una notificación con el número ganador.',
        img: 'assets/images/play/play_step_09.png',
      ),
      _PlayStep(
        title: '10) Historial: resultado “Perdido”',
        desc:
            'En “Historial” el estado cambia de “En juego” a “Perdido” si el número ganador NO está entre tus 5 números.',
        img: 'assets/images/play/play_step_10.png',
      ),
      _PlayStep(
        title: '11) Historial: resultado “Ganado”',
        desc:
            'Si alguno de tus 5 números coincide con el número ganador, el estado del juego pasa a “Ganado”. ¡Felicidades!',
        img: 'assets/images/play/play_step_11.png',
      ),
      _PlayStep(
        title: '12) Volver a jugar',
        desc:
            'En la pestaña “Juego actual” vuelve a aparecer el botón “JUGAR” para que puedas participar de nuevo en próximos juegos.',
        img: 'assets/images/play/play_step_12.png',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('¿Cómo jugar y registrar mis números?')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Guía paso a paso',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (final s in steps) ...[
              _StepTitle(s.title),
              const SizedBox(height: 6),
              Text(s.desc, style: const TextStyle(height: 1.35)),
              const SizedBox(height: 8),
              _ShotWithCaption(imagePath: s.img, caption: ''),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/* ======= helpers ======= */

class _PlayStep {
  final String title;
  final String desc;
  final String img;
  _PlayStep({required this.title, required this.desc, required this.img});
}

class _StepTitle extends StatelessWidget {
  final String text;
  const _StepTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w700));
  }
}

class _ShotWithCaption extends StatelessWidget {
  final String imagePath;
  final String caption;
  const _ShotWithCaption({required this.imagePath, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  alignment: Alignment.center,
                  color: Colors.black12,
                  child: Text(
                    'No se encontró $imagePath',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    );
  }
}
