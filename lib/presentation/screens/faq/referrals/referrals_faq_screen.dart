import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ReferralsFaqScreen extends StatelessWidget {
  const ReferralsFaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Guía del programa de referidos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Invita amigos, ellos se registran con tu código y, si compran una suscripción, recibes una comisión. '
            'A continuación te explicamos el proceso completo.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          _SectionCard(
            title: '1) Tu código de referido',
            children: const [
              _Bullet('Al registrarte, recibes un código único de referido.'),
              _Bullet('Compártelo con tus amigos. Ellos deben ingresar ese código al registrarse.'),
            ],
          ),

          _SectionCard(
            title: '2) ¿Cuándo ganas comisión?',
            children: const [
              _Bullet('Cuando tu referido compra una suscripción usando tu código.'),
              _Bullet('Plan PRO 60.000 COP → comisión del 40%.'),
              _Bullet('Plan PRO 20.000 COP → comisión del 20%.'),
            ],
          ),

          _SectionCard(
            title: '3) Estados de tu dinero',
            children: const [
              _SubTitle('Retenido (3 días)'),
              _Bullet('Al producirse una compra, la comisión entra como “Retenida” por 3 días.'),
              _Bullet('Este periodo evita fraudes o reembolsos que anularían la comisión.'),
              _SubTitle('Disponible'),
              _Bullet('Tras 3 días sin reembolso, la comisión pasa a “Disponible”.'),
            ],
          ),

          _SectionCard(
            title: '4) ¿Cuándo puedo retirar?',
            children: const [
              _Bullet('Cuando acumules al menos 100.000 COP en “Disponible”.'),
              _Bullet('Al alcanzar el umbral, verás habilitado el botón “Solicitar retiro”.'),
            ],
          ),

          _SectionCard(
            title: '5) Solicitar retiro',
            children: const [
              _Bullet('Si eliges banco: deberás indicar Banco, Tipo de cuenta y Número de cuenta.'),
              _Bullet('Si eliges billetera (Nequi, Daviplata, Movii, etc.): solo se solicitará el número de celular.'),
              _Bullet('Envía la solicitud. Nuestro equipo valida los datos y procesa el pago.'),
            ],
          ),

          _SectionCard(
            title: '6) ¿Qué pasa después de enviar la solicitud?',
            children: const [
              _SubTitle('Aprobada'),
              _Bullet('Recibirás una notificación confirmando el pago con la evidencia del giro.'),
              _SubTitle('Rechazada'),
              _Bullet('Si los datos son incorrectos o hay inconsistencia, la solicitud puede ser rechazada.'),
              _Bullet('Te llegará una notificación con el motivo. El dinero vuelve a “Disponible” para que corrijas y vuelvas a solicitar.'),
            ],
          ),

          _SectionCard(
            title: '7) Buenas prácticas para asegurar tu comisión',
            children: const [
              _Bullet('Asegúrate de que tu amigo ingrese tu código al registrarse.'),
              _Bullet('Pide al referido que complete la compra desde su cuenta y con conexión estable.'),
              _Bullet('Recuerda que la comisión se libera a “Disponible” tras 3 días sin reembolso.'),
            ],
          ),

          const SizedBox(height: 12),
          Divider(color: theme.dividerColor),
          const SizedBox(height: 12),

          _InfoBox(
            title: '¿Tienes dudas o un caso específico?',
            text:
                'Escríbenos por WhatsApp indicando el usuario referido, fecha de compra y método de pago. '
                'Revisaremos tu caso y te responderemos con la trazabilidad.',
            actionLabel: 'Contactar soporte',
            url: 'https://wa.me/573218597037',
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.check_circle_outline, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String title;
  final String text;
  final String actionLabel;
  final String url;

  const _InfoBox({
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.url,
  });

  Future<void> _launchUrl() async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(text, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _launchUrl,
              icon: const Icon(Icons.support_agent),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
