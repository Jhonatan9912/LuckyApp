// lib/web/web_shell.dart
//
// Marco de la versión web. Las pantallas ya rediseñadas para web ocupan todo
// el ancho; las que aún usan el diseño móvil se muestran centradas, con el
// ancho de un teléfono, sobre el fondo animado de la marca.
import 'package:flutter/material.dart';

import 'alerts/web_alerts.dart';
import 'theme/web_palette.dart';
import 'widgets/aurora_background.dart';

/// Rutas con diseño web propio (se muestran a ancho completo).
const Set<String> kWebFullWidthRoutes = {
  '/',
  '/login',
  '/registro',
  '/dashboard',
  '/admin',
  '/restablecer',
  '/terminos',
  '/datos',
};

/// Pantallas que se pueden abrir sin sesión desde un enlace directo.
const Set<String> kWebPublicRoutes = {
  '/login',
  '/registro',
  '/restablecer',
  '/terminos',
  '/datos',
};

/// Sigue cuál es la página visible (ignora diálogos y hojas inferiores).
class WebRouteTracker extends NavigatorObserver {
  final ValueNotifier<String?> current = ValueNotifier<String?>('/');
  final List<Route<dynamic>> _pages = [];

  void _sync() {
    current.value = _pages.isEmpty ? null : _pages.last.settings.name;
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PageRoute) {
      _pages.add(route);
      _sync();
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (_pages.remove(route)) _sync();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (_pages.remove(route)) _sync();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (newRoute is PageRoute) {
      if (i >= 0) {
        _pages[i] = newRoute;
      } else {
        _pages.add(newRoute);
      }
    } else if (i >= 0) {
      _pages.removeAt(i);
    }
    _sync();
  }
}

final WebRouteTracker webRouteTracker = WebRouteTracker();

/// `MaterialApp.builder` para web.
Widget webAppBuilder(BuildContext context, Widget? child) {
  return ValueListenableBuilder<String?>(
    valueListenable: webRouteTracker.current,
    child: child,
    builder: (context, name, child) {
      final full = name != null && kWebFullWidthRoutes.contains(name);
      final page = child ?? const SizedBox.shrink();
      return Stack(
        children: [
          Positioned.fill(child: full ? page : _PhoneFrame(child: page)),
          // Avisos y modales modernos sobre toda la ventana
          const Positioned.fill(child: WebAlertsHost()),
        ],
      );
    },
  );
}

class _PhoneFrame extends StatelessWidget {
  final Widget child;
  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // En pantallas pequeñas no se enmarca: se usa todo el ancho.
    if (width < 600) return child;

    return AuroraBackground(
      showGrid: false,
      animate: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: WebPalette.gold.withValues(alpha: 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 60,
                  offset: const Offset(0, 30),
                ),
                BoxShadow(
                  color: WebPalette.gold.withValues(alpha: 0.10),
                  blurRadius: 80,
                  spreadRadius: -20,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
