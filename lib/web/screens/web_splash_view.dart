// lib/web/screens/web_splash_view.dart
import 'package:flutter/material.dart';

import '../theme/web_palette.dart';
import '../widgets/aurora_background.dart';

/// Pantalla de carga de la web: logo con pulso dorado.
class WebSplashView extends StatefulWidget {
  const WebSplashView({super.key});

  @override
  State<WebSplashView> createState() => _WebSplashViewState();
}

class _WebSplashViewState extends State<WebSplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebPalette.bg,
      body: AuroraBackground(
        showGrid: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (context, child) => Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: WebPalette.gold.withValues(
                          alpha: 0.15 + 0.25 * _c.value,
                        ),
                        blurRadius: 40 + 40 * _c.value,
                      ),
                    ],
                  ),
                  child: Transform.scale(
                    scale: 0.96 + 0.06 * _c.value,
                    child: child,
                  ),
                ),
                child: Image.asset('assets/icons/iconowithout.png', width: 120),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: WebPalette.gold,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
