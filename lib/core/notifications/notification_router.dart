// lib/core/notifications/notification_router.dart
//
// Decide a qué pantalla navegar cuando el usuario toca una notificación.
// Usa navigatorKey para navegar sin BuildContext local.

import 'package:flutter/material.dart';

class NotificationRouter {
  final GlobalKey<NavigatorState> navigatorKey;

  NotificationRouter({required this.navigatorKey});

  /// Navega según los datos del payload (message.data o payload local).
  /// Formatos soportados:
  /// 1) {"route": "/faq/pro"}
  /// 2) {"type": "open_faq_referidos"}
  /// 3) {"type": "open_paywall"}  // abre /pro
  /// 4) {"type": "commission_available"} // ejemplo: ir al dashboard
  Future<void> handle(Map<String, dynamic> data) async {
    if (data.isEmpty) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    // 1) Navegación directa por ruta si viene "route"
    final route = _asString(data['route']);
    if (route != null && route.isNotEmpty) {
      await _safePushNamed(route);
      return;
    }

    // 2) Mapeo por tipo
    final type = _asString(data['type']);
    switch (type) {
      case 'open_faq_pro':
        await _safePushNamed('/faq/pro');
        return;
      case 'open_faq_referidos':
        await _safePushNamed('/faq/referidos');
        return;
      case 'open_paywall':
        await _safePushNamed('/pro');
        return;

      // Eventos de negocio (ajusta si cambias tus rutas)
      case 'commission_available':
      case 'payout_approved':
      case 'payout_rejected':
        await _safePushNamed('/dashboard');
        return;

      default:
        // Fallback sensato: tablero
        await _safePushNamed('/dashboard');
        return;
    }
  }

  // =============== helpers ===============

  String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  Future<void> _safePushNamed(String route) async {
    // Limpia posibles stacks “raros” cuando se toca desde estado terminado
    navigatorKey.currentState!
        .pushNamedAndRemoveUntil(route, (route) => false);
  }
}
