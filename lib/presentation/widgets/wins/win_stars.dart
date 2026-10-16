// lib/presentation/widgets/wins/win_stars.dart
//
// Estrellas de ganador: se calculan solas a partir de las victorias del
// usuario (juegos cuyo número ganador estaba entre sus números).
//
// Para no llenar el perfil de estrellas:
//   - 1 a 3 victorias  → se ven las estrellas una por una.
//   - 4 o más          → una sola estrella con el contador (★ ×20).
// El color de la estrella sube de nivel: Bronce → Plata → Oro → Diamante.
//
// Se usa igual en la app y en la web (jugador y administrador).
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Nivel de ganador según la cantidad de victorias.
class WinTier {
  final String name;
  final int minWins;
  final List<Color> colors; // oscuro, brillo, base

  const WinTier(this.name, this.minWins, this.colors);

  Color get base => colors[2];
  Color get light => colors[1];

  static const bronze = WinTier('Bronce', 1, [
    Color(0xFF8C5A2B),
    Color(0xFFF2C08D),
    Color(0xFFC98443),
  ]);
  static const silver = WinTier('Plata', 5, [
    Color(0xFF7D8894),
    Color(0xFFFFFFFF),
    Color(0xFFC3CCD5),
  ]);
  static const gold = WinTier('Oro', 10, [
    Color(0xFFB8860B),
    Color(0xFFFFEC99),
    Color(0xFFF5C842),
  ]);
  static const diamond = WinTier('Diamante', 20, [
    Color(0xFF6C5CE7),
    Color(0xFFE6FBFF),
    Color(0xFF3FD8FF),
  ]);

  static const all = [bronze, silver, gold, diamond];

  /// null si todavía no tiene victorias.
  static WinTier? of(int wins) {
    WinTier? t;
    for (final tier in all) {
      if (wins >= tier.minWins) t = tier;
    }
    return t;
  }

  /// Siguiente nivel, o null si ya está en el máximo.
  static WinTier? next(int wins) {
    for (final tier in all) {
      if (wins < tier.minWins) return tier;
    }
    return null;
  }
}

/// Máximo de estrellas sueltas antes de agruparlas en "★ ×N".
const int _maxLooseStars = 3;

const Color _badgeBg = Color(0xFF15151A);
const Color _mutedStar = Color(0xFF6B6B75);

/// Insignia compacta con las estrellas del usuario.
///
/// - [showEmpty]: si es true y no hay victorias, muestra una estrella apagada
///   (útil para el propio jugador); si es false no ocupa espacio (listas admin).
/// - [onTap]: si es null abre el detalle de victorias.
class WinStarsBadge extends StatefulWidget {
  final int wins;
  final double size;
  final bool showEmpty;
  final VoidCallback? onTap;

  const WinStarsBadge({
    super.key,
    required this.wins,
    this.size = 16,
    this.showEmpty = false,
    this.onTap,
  });

  @override
  State<WinStarsBadge> createState() => _WinStarsBadgeState();
}

class _WinStarsBadgeState extends State<WinStarsBadge>
    with TickerProviderStateMixin {
  // Entrada: las estrellas aparecen una tras otra con rebote.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  // Brillo que recorre la estrella (solo Oro y Diamante, para que se note
  // el nivel y no gastar animaciones en listas largas).
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _syncShine();
  }

  @override
  void didUpdateWidget(covariant WinStarsBadge old) {
    super.didUpdateWidget(old);
    // Ganó de nuevo: se repite la animación de celebración.
    if (widget.wins > old.wins) _intro.forward(from: 0);
    _syncShine();
  }

  void _syncShine() {
    final tier = WinTier.of(widget.wins);
    final shiny = tier != null && tier.minWins >= WinTier.gold.minWins;
    if (shiny && !_shine.isAnimating) {
      _shine.repeat();
    } else if (!shiny && _shine.isAnimating) {
      _shine.stop();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wins = widget.wins;
    final tier = WinTier.of(wins);
    if (tier == null && !widget.showEmpty) return const SizedBox.shrink();

    final s = widget.size;
    final grouped = wins > _maxLooseStars;
    final looseCount = tier == null ? 1 : (grouped ? 1 : wins);

    Widget star(int i) {
      // Cada estrella entra un poco después de la anterior.
      final start = (i * 0.18).clamp(0.0, 0.6);
      final anim = CurvedAnimation(
        parent: _intro,
        curve: Interval(start, math.min(1.0, start + 0.55),
            curve: Curves.elasticOut),
      );
      return ScaleTransition(
        scale: anim,
        child: tier == null
            ? Icon(Icons.star_outline_rounded, size: s, color: _mutedStar)
            : _ShinyStar(tier: tier, size: s, shine: _shine),
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < looseCount; i++) star(i),
        if (grouped)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _intro,
                curve: const Interval(0.3, 1),
              ),
              child: Text(
                '×$wins',
                style: TextStyle(
                  color: tier!.light,
                  fontSize: s * 0.78,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );

    final border = tier?.base ?? _mutedStar;
    final tooltip = tier == null
        ? 'Aún no has ganado. ¡Tu primera estrella te espera!'
        : '$wins ${wins == 1 ? 'victoria' : 'victorias'} · Nivel ${tier.name}';

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap ?? () => showWinStarsDetails(context, wins),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s * 0.45, vertical: 3),
            decoration: BoxDecoration(
              color: _badgeBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border.withValues(alpha: 0.55)),
              boxShadow: tier == null
                  ? null
                  : [
                      BoxShadow(
                        color: tier.base.withValues(alpha: 0.30),
                        blurRadius: 8,
                      ),
                    ],
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Estrella con el degradado del nivel y un brillo que la recorre.
class _ShinyStar extends StatelessWidget {
  final WinTier tier;
  final double size;
  final Animation<double> shine;

  const _ShinyStar({
    required this.tier,
    required this.size,
    required this.shine,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shine,
      builder: (_, child) {
        final t = shine.isAnimating ? shine.value : 0.5;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tier.colors[0], tier.base, tier.light, tier.base],
            stops: const [0.0, 0.35, 0.5, 0.65],
            transform: _SlideGradient(t * 2 - 1),
          ).createShader(rect),
          child: child,
        );
      },
      child: Icon(Icons.star_rounded, size: size, color: Colors.white),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double offset; // -1..1
  const _SlideGradient(this.offset);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * offset, bounds.height * offset, 0);
}

/// Detalle animado de las victorias del usuario: estrella grande, contador,
/// nivel actual y cuánto falta para el siguiente.
Future<void> showWinStarsDetails(
  BuildContext context,
  int wins, {
  String? userName,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, _, _) =>
        _WinStarsDialog(wins: wins, userName: userName),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
        child: child,
      ),
    ),
  );
}

class _WinStarsDialog extends StatefulWidget {
  final int wins;
  final String? userName;

  const _WinStarsDialog({required this.wins, this.userName});

  @override
  State<_WinStarsDialog> createState() => _WinStarsDialogState();
}

class _WinStarsDialogState extends State<_WinStarsDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wins = widget.wins;
    final tier = WinTier.of(wins);
    final next = WinTier.next(wins);
    final color = tier?.base ?? _mutedStar;
    final name = widget.userName?.trim() ?? '';

    final title = tier == null
        ? (name.isEmpty ? 'Aún sin victorias' : '$name aún no ha ganado')
        : (name.isEmpty
              ? '¡Has ganado $wins ${wins == 1 ? 'vez' : 'veces'}!'
              : '$name ha ganado $wins ${wins == 1 ? 'vez' : 'veces'}');

    // Progreso dentro del nivel actual hacia el siguiente.
    final from = tier?.minWins ?? 0;
    final progress = next == null
        ? 1.0
        : ((wins - from) / (next.minWins - from)).clamp(0.0, 1.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          decoration: BoxDecoration(
            color: _badgeBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 40),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Estrella grande con halo giratorio.
              SizedBox(
                width: 130,
                height: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (tier != null)
                      RotationTransition(
                        turns: _spin,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                color.withValues(alpha: 0),
                                color.withValues(alpha: 0.45),
                                color.withValues(alpha: 0),
                                tier.light.withValues(alpha: 0.35),
                                color.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.elasticOut,
                      builder: (_, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: tier == null
                          ? const Icon(
                              Icons.star_outline_rounded,
                              size: 92,
                              color: _mutedStar,
                            )
                          : _ShinyStar(tier: tier, size: 92, shine: _spin),
                    ),
                    if (tier != null)
                      // Contador que sube desde 0.
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: wins.toDouble()),
                        duration: const Duration(milliseconds: 1100),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${v.round()}',
                            style: TextStyle(
                              color: _badgeBg,
                              fontSize: wins >= 100 ? 20 : 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tier == null
                    ? 'Cada vez que uno de tus números sea el ganador sumarás una estrella.'
                    : 'Nivel ${tier.name}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tier == null ? Colors.white70 : tier.light,
                  fontSize: 14,
                  fontWeight: tier == null ? FontWeight.w400 : FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),

              // Escalera de niveles.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final t in WinTier.all)
                    _TierStep(tier: t, reached: wins >= t.minWins),
                ],
              ),
              const SizedBox(height: 14),

              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 8,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(
                      next?.base ?? color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                next == null
                    ? '¡Nivel máximo alcanzado!'
                    : 'Faltan ${next.minWins - wins} '
                          '${next.minWins - wins == 1 ? 'victoria' : 'victorias'} '
                          'para ${next.name}',
                style: const TextStyle(color: Colors.white60, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cerrar',
                  style: TextStyle(color: tier?.light ?? Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierStep extends StatelessWidget {
  final WinTier tier;
  final bool reached;

  const _TierStep({required this.tier, required this.reached});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedOpacity(
          opacity: reached ? 1 : 0.35,
          duration: const Duration(milliseconds: 400),
          child: Icon(
            reached ? Icons.star_rounded : Icons.lock_outline_rounded,
            size: 22,
            color: reached ? tier.base : Colors.white54,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${tier.name}\n${tier.minWins}+',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: reached ? tier.light : Colors.white38,
            fontSize: 10.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
