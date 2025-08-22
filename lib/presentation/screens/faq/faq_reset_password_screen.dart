import 'package:flutter/material.dart';

class FaqResetPasswordScreen extends StatelessWidget {
  const FaqResetPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cómo restablecer la contraseña')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _Title('Guía paso a paso'),

            SizedBox(height: 10),
            _Paragraph(
              '1) En la pantalla de inicio de sesión toca "Restablecer contraseña". '
              'Ingresa tu correo y presiona "Enviar código".',
            ),
            SizedBox(height: 8),
            _ShotWithCaption(
              imagePath: 'assets/images/faq/reset_step_1.png',
              caption: 'Pantalla para solicitar el código al correo.',
            ),

            SizedBox(height: 16),
            _Paragraph(
              '2) Revisa el correo y escribe el código de verificación. '
              'Luego toca "Validar código".',
            ),
            SizedBox(height: 8),
            _ShotWithCaption(
              imagePath: 'assets/images/faq/reset_step_2.png',
              caption: 'Ingresa el código de verificación y valida.',
            ),

            SizedBox(height: 16),
            _Paragraph(
              '3) Define tu nueva contraseña y confírmala. '
              'Asegúrate de recordar la nueva clave.',
            ),
            SizedBox(height: 8),
            _ShotWithCaption(
              imagePath: 'assets/images/faq/reset_step_3.png',
              caption: 'Escribe y confirma tu nueva contraseña.',
            ),

            SizedBox(height: 16),
            _Paragraph(
              '4) Presiona "Restablecer contraseña" para finalizar. '
              'Serás redirigido para iniciar sesión con tu nueva clave.',
            ),
            SizedBox(height: 8),
            _ShotWithCaption(
              imagePath: 'assets/images/faq/reset_step_4.png',
              caption: 'Confirma el cambio para completar el proceso.',
            ),

            SizedBox(height: 20),
            _Title('Consejos'),
            SizedBox(height: 8),
            _Bullet('Si no llega el correo, revisa spam o espera unos minutos.'),
            _Bullet('No reutilices contraseñas de otros sitios.'),
            _Bullet('Usa al menos 8 caracteres y combina letras y números.'),
          ],
        ),
      ),
    );
  }
}

/* ======= Widgets pequeños para texto e imágenes ======= */

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(height: 1.35));
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ShotWithCaption extends StatelessWidget {
  final String imagePath;
  final String caption;
  const _ShotWithCaption({required this.imagePath, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, // 👈 centra el caption también
      children: [
        Center( // 👈 centra la imagen
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360), // opcional: ancho máximo “bonito”
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
        const SizedBox(height: 6),
        Text(
          caption,
          textAlign: TextAlign.center, // 👈 centra el texto del pie
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

