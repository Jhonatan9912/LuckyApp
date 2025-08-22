import 'package:flutter/material.dart';

class HelpBottomSheet extends StatelessWidget {
  const HelpBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Preguntas frecuentes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),

            // ¿Cómo juego...?
            ListTile(
              leading: const Icon(Icons.question_answer),
              title: const Text('¿Cómo juego y registro mis números?'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/faq/juego');
              },
            ),

            // Restablecer contraseña
            ListTile(
              leading: const Icon(Icons.key), // o Icons.password
              title: const Text('Cómo restablecer la contraseña'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/faq/restablecer');
              },
            ),

// Soporte (deshabilitado por ahora). Quitar el bloque de comentarios cuando esté listo.
/*
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('Soporte'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/soporte');
              },
            ),
            */
          ],
        ),
      ),
    );
  }
}
