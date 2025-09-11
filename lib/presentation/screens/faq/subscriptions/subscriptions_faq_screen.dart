import 'package:flutter/material.dart';
import 'widgets/step_card.dart';

class SubscriptionsFaqScreen extends StatelessWidget {
  const SubscriptionsFaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Actualizar suscripción PRO')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: const [
          StepCard(
            stepNumber: 1,
            title: 'Abrir la pantalla de suscripción',
            description:
                'Desde la app, entra en el apartado de suscripción para gestionar tu plan PRO.',
            imageAsset: 'assets/images/subscriptions/subscription1.jpg',
          ),
          StepCard(
            stepNumber: 2,
            title: 'Presionar “Restaurar compras”',
            description:
                'Si ya pagaste y PRO no aparece activo, toca el botón de “Restaurar compras” para sincronizar tu suscripción.',
            imageAsset: 'assets/images/subscriptions/subscription2.jpg',
          ),
          StepCard(
            stepNumber: 3,
            title: 'Confirmar PRO activo',
            description:
                'Una vez restaurada la compra, deberías ver PRO activado con todas las funciones desbloqueadas.',
            imageAsset: 'assets/images/subscriptions/subscription3.jpg',
          ),
        ],
      ),
    );
  }
}
