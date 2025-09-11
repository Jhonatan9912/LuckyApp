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
              leading: const Icon(Icons.key),
              title: const Text('Cómo restablecer la contraseña'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/faq/restablecer');
              },
            ),

            // Actualizar versión PRO
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Cómo actualizar a la versión PRO'),
              subtitle: const Text(
                'Si ya te suscribiste y no aparece, entra en “Gestionar suscripción” y presiona “Restaurar compras”.',
                style: TextStyle(fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/faq/pro');
              },
            ),

            // Ganar con referidos
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Guía del programa de referidos'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/faq/referidos');
              },
            ),

            // Soporte (deshabilitado por ahora)
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
