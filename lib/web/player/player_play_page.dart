// lib/web/player/player_play_page.dart
//
// Página "Jugar": selector de modalidad, escenario de sorteo con balotas,
// acciones (Jugar / Reservar / Volver a intentar) y tarjetas laterales.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:base_app/core/config/links.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';
import 'package:base_app/presentation/screens/dashboard/controller/dashboard_controller.dart';

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import '../widgets/lottery_ball.dart';
import '../widgets/web_ui.dart';

class PlayerPlayPage extends StatelessWidget {
  final DashboardController ctrl;
  final bool hydrating;
  final bool currentGameClosed;
  final ValueChanged<int> onDigitsChanged;
  final Future<void> Function() onPlay;
  final Future<void> Function() onReserve;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenPlans;
  final VoidCallback onOpenReferrals;

  const PlayerPlayPage({
    super.key,
    required this.ctrl,
    required this.hydrating,
    required this.currentGameClosed,
    required this.onDigitsChanged,
    required this.onPlay,
    required this.onReserve,
    required this.onRetry,
    required this.onOpenPlans,
    required this.onOpenReferrals,
  });

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();
    final maxDigits = subs.maxDigits ?? 0;
    final digits = ctrl.digitsPerBall;

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeBar(
          digits: digits,
          maxDigits: maxDigits,
          disabled: ctrl.animating || ctrl.reserving,
          onChanged: onDigitsChanged,
        ),
        const SizedBox(height: 18),
        _DrawStage(
          ctrl: ctrl,
          hydrating: hydrating,
          canReserve: subs.isPremium && maxDigits >= digits,
          subsLoading: subs.loading || subs.activating,
          onPlay: onPlay,
          onReserve: onReserve,
          onRetry: onRetry,
          onOpenPlans: onOpenPlans,
        ),
        const SizedBox(height: 18),
        _ReservationPanel(
          ctrl: ctrl,
          hydrating: hydrating,
          closed: currentGameClosed,
          canReserve: subs.isPremium && maxDigits >= digits,
          onOpenPlans: onOpenPlans,
        ),
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlanCard(onOpenPlans: onOpenPlans),
        const SizedBox(height: 18),
        _ReferralCard(
          code: ctrl.referralCode,
          onOpen: onOpenReferrals,
          onOpenPlans: onOpenPlans,
        ),
        const SizedBox(height: 18),
        const _CommunityCard(),
      ],
    );

    return WebPage(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 980) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [main, const SizedBox(height: 18), side],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 13, child: main),
                const SizedBox(width: 22),
                Expanded(flex: 6, child: side),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ───────────────────────── Modalidad ─────────────────────────

class _ModeBar extends StatelessWidget {
  final int digits;
  final int maxDigits;
  final bool disabled;
  final ValueChanged<int> onChanged;

  const _ModeBar({
    required this.digits,
    required this.maxDigits,
    required this.disabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = [
      (2, '2 cifras'),
      (3, '3 cifras'),
      (4, '4 cifras'),
      (5, 'Quinta'),
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Modalidad',
              style: WebPalette.display(18, weight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Elige con cuántas cifras quieres jugar.',
              style: WebPalette.body(13.5),
            ),
          ],
        ),
        IgnorePointer(
          ignoring: disabled,
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: WebSegmented<int>(
              options: options,
              value: digits,
              locked: {
                for (final (d, _) in options)
                  if (d >= 4 && d > maxDigits) d,
              },
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Escenario ─────────────────────────

class _DrawStage extends StatefulWidget {
  final DashboardController ctrl;
  final bool hydrating;
  final bool canReserve;
  final bool subsLoading;
  final Future<void> Function() onPlay;
  final Future<void> Function() onReserve;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenPlans;

  const _DrawStage({
    required this.ctrl,
    required this.hydrating,
    required this.canReserve,
    required this.subsLoading,
    required this.onPlay,
    required this.onReserve,
    required this.onRetry,
    required this.onOpenPlans,
  });

  @override
  State<_DrawStage> createState() => _DrawStageState();
}

class _DrawStageState extends State<_DrawStage> {
  int _revealed = 5;
  Timer? _timer;
  bool _wasAnimating = false;

  @override
  void didUpdateWidget(covariant _DrawStage old) {
    super.didUpdateWidget(old);
    _syncReveal();
  }

  @override
  void initState() {
    super.initState();
    _syncReveal();
  }

  void _syncReveal() {
    final animating = widget.ctrl.animating;
    if (animating && !_wasAnimating) {
      // Revela una balota por segundo, como en la app.
      _timer?.cancel();
      _revealed = 0;
      _timer = Timer.periodic(const Duration(milliseconds: 900), (t) {
        if (!mounted) return t.cancel();
        setState(() => _revealed++);
        if (_revealed >= 5) t.cancel();
      });
      Future.microtask(() {
        if (mounted) setState(() => _revealed = 1);
      });
    } else if (!animating && _wasAnimating) {
      _timer?.cancel();
      _revealed = 5;
    }
    _wasAnimating = animating;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final digits = ctrl.digitsPerBall;
    // Si ya hay una reserva restaurada (sin haber jugado en esta sesión),
    // el escenario muestra esos números en lugar de balotas vacías.
    final restored =
        !ctrl.hasPlayedOnce && ctrl.hasAdded && ctrl.displayedBalls.isNotEmpty;
    final played = ctrl.hasPlayedOnce || restored;
    final nums = restored ? ctrl.displayedBalls : ctrl.numbers;
    final ballSize = MediaQuery.sizeOf(context).width < 600 ? 54.0 : 82.0;

    return WebPanel(
      highlight: true,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Juego actual',
                      style: WebPalette.display(22, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ctrl.animating
                          ? 'Sorteando tus números…'
                          : ctrl.reserving
                          ? 'Reservando tu jugada…'
                          : (ctrl.hasAdded && ctrl.displayedBalls.isNotEmpty)
                          ? 'Estos números ya están reservados a tu nombre.'
                          : played
                          ? 'Estos son tus números. ¿Los reservas?'
                          : 'Presiona JUGAR para generar 5 números al azar.',
                      style: WebPalette.body(14),
                    ),
                  ],
                ),
              ),
              if (ctrl.gameId != null)
                StatusChip(
                  label: 'Juego #${ctrl.gameId}',
                  color: WebPalette.goldLight,
                ),
            ],
          ),
          const SizedBox(height: 28),
          // Balotas
          SizedBox(
            height: ballSize * 1.5,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ballSize * 0.12,
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          // Durante la reserva se atenúan las que faltan por revelar.
                          opacity:
                              ctrl.reserving && i >= ctrl.displayedBalls.length
                              ? 0.3
                              : 1,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 450),
                            transitionBuilder: (child, a) => ScaleTransition(
                              scale: CurvedAnimation(
                                parent: a,
                                curve: Curves.easeOutBack,
                              ),
                              child: FadeTransition(opacity: a, child: child),
                            ),
                            child: (played && i < _revealed && i < nums.length)
                                ? LotteryBall(
                                    key: ValueKey('n$i-${nums[i]}-$digits'),
                                    number: formatGameNumber(nums[i], digits),
                                    size: ballSize,
                                    floatPhase: i * 1.1,
                                  )
                                : LotteryBall(
                                    key: ValueKey('e$i'),
                                    number: '?',
                                    size: ballSize,
                                    dark: true,
                                    floatPhase: i * 1.1,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          _actions(),
        ],
      ),
    );
  }

  Widget _actions() {
    final ctrl = widget.ctrl;
    if (widget.hydrating) {
      return const Center(
        child: SkeletonBlock(height: 54, width: 260, radius: 14),
      );
    }

    Widget play(String label) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: GoldButton(
          label: label,
          icon: Icons.casino_rounded,
          loading: ctrl.animating,
          onPressed: (ctrl.animating || ctrl.saving) ? null : widget.onPlay,
        ),
      ),
    );

    if (widget.subsLoading) {
      return ctrl.hasPlayedOnce ? const SizedBox.shrink() : play('JUGAR');
    }

    if (!widget.canReserve) {
      return Column(
        children: [
          play(ctrl.hasPlayedOnce ? 'JUGAR DE NUEVO' : 'JUGAR'),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: WebPalette.textFaint,
              ),
              Text(
                'Vista previa. Para reservar necesitas un plan con esta modalidad.',
                textAlign: TextAlign.center,
                style: WebPalette.body(13),
              ),
              HoverLink(
                text: 'Ver planes',
                size: 13,
                onTap: widget.onOpenPlans,
              ),
            ],
          ),
        ],
      );
    }

    if (ctrl.showFinalButtons) {
      if (ctrl.reserving || ctrl.hasAddedFinal) return const SizedBox.shrink();
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 240,
            child: GoldButton(
              label: 'RESERVAR',
              icon: Icons.check_rounded,
              loading: ctrl.saving,
              onPressed: ctrl.saving ? null : widget.onReserve,
            ),
          ),
          GhostButton(
            label: 'Volver a intentar',
            icon: Icons.refresh_rounded,
            onPressed: ctrl.saving ? null : widget.onRetry,
          ),
        ],
      );
    }

    if (!ctrl.hasPlayedOnce) return play('JUGAR');
    return const SizedBox.shrink();
  }
}

// ───────────────────────── Reserva ─────────────────────────

class _ReservationPanel extends StatelessWidget {
  final DashboardController ctrl;
  final bool hydrating;
  final bool closed;
  final bool canReserve;
  final VoidCallback onOpenPlans;

  const _ReservationPanel({
    required this.ctrl,
    required this.hydrating,
    required this.closed,
    required this.canReserve,
    required this.onOpenPlans,
  });

  @override
  Widget build(BuildContext context) {
    final digits = ctrl.digitsPerBall;
    final hasReservation =
        ctrl.hasAdded && !closed && ctrl.displayedBalls.isNotEmpty;

    Widget body;
    if (hydrating) {
      body = const SkeletonBlock(height: 48);
    } else if (!canReserve) {
      body = Row(
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            color: WebPalette.goldLight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Activa un plan para reservar tus números y participar en los sorteos.',
              style: WebPalette.body(14),
            ),
          ),
          const SizedBox(width: 12),
          GhostButton(label: 'Ver planes', onPressed: onOpenPlans),
        ],
      );
    } else if (hasReservation) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NumberPills([
            for (final n in ctrl.displayedBalls) formatGameNumber(n, digits),
          ]),
          const SizedBox(height: 12),
          Text(
            ctrl.reserving
                ? 'Guardando tu reserva…'
                : 'Estos números ya están a tu nombre. Te avisaremos cuando se programe el sorteo.',
            style: WebPalette.body(13.5),
          ),
        ],
      );
    } else {
      body = Text(
        'Aún no tienes números reservados en esta modalidad. Juega y presiona RESERVAR para guardarlos.',
        style: WebPalette.body(14),
      );
    }

    return WebPanel(
      title: 'Tu reserva',
      subtitle: 'Modalidad de ${digits == 5 ? 'Quinta' : '$digits cifras'}',
      icon: Icons.confirmation_number_outlined,
      actions: [
        if (hasReservation)
          const StatusChip(
            label: 'Reservado',
            color: WebPalette.emerald,
            icon: Icons.check_rounded,
          ),
      ],
      child: body,
    );
  }
}

// ───────────────────────── Laterales ─────────────────────────

class _PlanCard extends StatelessWidget {
  final VoidCallback onOpenPlans;
  const _PlanCard({required this.onOpenPlans});

  String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();
    final pro = subs.isPremium;
    final label = !pro
        ? 'Sin plan activo'
        : subs.isTrial
        ? 'Prueba gratuita'
        : 'Plan activo';
    final maxD = subs.maxDigits;

    return WebPanel(
      highlight: pro,
      title: 'Mi plan',
      icon: Icons.workspace_premium_outlined,
      actions: [
        StatusChip(
          label: pro ? (subs.isTrial ? 'PRUEBA' : 'PRO') : 'FREE',
          color: pro ? WebPalette.goldLight : WebPalette.textFaint,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: WebPalette.display(20, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            pro
                ? 'Puedes jugar hasta ${maxD == 5 ? 'Quinta (5 cifras)' : '${maxD ?? 3} cifras'}. Vence: ${_fmt(subs.expiresAt)}'
                : 'Puedes ver la vista previa del juego. Activa un plan para reservar números.',
            style: WebPalette.body(13.5),
          ),
          const SizedBox(height: 16),
          pro
              ? GhostButton(
                  label: 'Ver detalles del plan',
                  icon: Icons.tune_rounded,
                  onPressed: onOpenPlans,
                )
              : GoldButton(
                  label: 'Ver planes',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onOpenPlans,
                ),
        ],
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  final String? code;
  final VoidCallback onOpen;
  final VoidCallback onOpenPlans;
  const _ReferralCard({
    required this.code,
    required this.onOpen,
    required this.onOpenPlans,
  });

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();
    final refs = context.watch<ReferralProvider>();

    if (!subs.isPaidPremium) {
      return WebPanel(
        title: 'Gana con referidos',
        icon: Icons.groups_2_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              subs.isTrial
                  ? 'Durante la prueba gratuita no se generan comisiones. Activa un plan pagado para ganar con tus referidos.'
                  : 'Invita amigos con tu código y gana comisión cuando compren un plan. Disponible con un plan pagado.',
              style: WebPalette.body(13.5),
            ),
            const SizedBox(height: 14),
            GhostButton(
              label: 'Ver planes',
              icon: Icons.workspace_premium_outlined,
              onPressed: onOpenPlans,
            ),
          ],
        ),
      );
    }

    return WebPanel(
      title: 'Tus referidos',
      icon: Icons.groups_2_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Disponible para retiro',
            style: WebPalette.body(12.5, color: WebPalette.textFaint),
          ),
          const SizedBox(height: 4),
          Text(
            fmtCop(refs.availableCop),
            style: WebPalette.display(26, weight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          if ((code ?? '').isNotEmpty) ReferralCodeBox(code: code!),
          const SizedBox(height: 14),
          GhostButton(
            label: 'Ver mis referidos',
            icon: Icons.arrow_forward_rounded,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

/// Caja con el código de referido y botón de copiar.
class ReferralCodeBox extends StatelessWidget {
  final String code;
  const ReferralCodeBox({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.25),
        border: Border.all(color: WebPalette.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu código',
                  style: WebPalette.body(11.5, color: WebPalette.textFaint),
                ),
                SelectableText(
                  code,
                  style: WebPalette.display(
                    18,
                    weight: FontWeight.w800,
                    color: WebPalette.goldLight,
                  ),
                ),
              ],
            ),
          ),
          WebIconButton(
            icon: Icons.copy_rounded,
            tooltip: 'Copiar código',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              WebAlerts.toast(
                'Código $code copiado al portapapeles.',
                tone: AlertTone.success,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard();

  @override
  Widget build(BuildContext context) {
    Widget link(IconData icon, String label, String url, Color color) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LinkTile(icon: icon, label: label, color: color, url: url),
        );

    return WebPanel(
      title: 'Comunidad y soporte',
      icon: Icons.forum_outlined,
      child: Column(
        children: [
          link(
            Icons.campaign_outlined,
            'Canal de WhatsApp',
            AppLinks.whatsappChannel,
            const Color(0xFF25D366),
          ),
          link(
            Icons.facebook_rounded,
            'Facebook',
            AppLinks.facebookShare,
            const Color(0xFF4C8BF5),
          ),
          link(
            Icons.support_agent_rounded,
            'Hablar con un asesor',
            AppLinks.whatsappAdvisor,
            WebPalette.goldLight,
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String url;
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.url,
  });

  @override
  State<_LinkTile> createState() => _LinkTileState();
}

class _LinkTileState extends State<_LinkTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => launchUrl(
          Uri.parse(widget.url),
          mode: LaunchMode.externalApplication,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: _hover ? 0.07 : 0.03),
            border: Border.all(
              color: _hover
                  ? widget.color.withValues(alpha: 0.5)
                  : WebPalette.glassBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: WebPalette.body(
                    14,
                    weight: FontWeight.w600,
                    color: WebPalette.text,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: _hover ? widget.color : WebPalette.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
