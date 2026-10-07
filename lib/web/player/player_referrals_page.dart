// lib/web/player/player_referrals_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:base_app/data/api/referrals_api.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';
import 'package:base_app/presentation/widgets/payout_request_sheet.dart';

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import '../widgets/web_ui.dart';
import 'player_play_page.dart' show ReferralCodeBox;

class PlayerReferralsPage extends StatelessWidget {
  final String? code;
  final VoidCallback onOpenPlans;

  const PlayerReferralsPage({
    super.key,
    required this.code,
    required this.onOpenPlans,
  });

  String _fmtDate(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _withdraw(BuildContext context) async {
    final refs = context.read<ReferralProvider>();
    final ok = await showPayoutRequestSheet(context);
    if (ok == true) {
      WebAlerts.toast(
        'Tu solicitud de retiro fue enviada. Te avisaremos cuando se procese.',
        title: 'Solicitud enviada',
        tone: AlertTone.success,
      );
      await refs.load(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();
    final refs = context.watch<ReferralProvider>();

    if (!subs.isPaidPremium) {
      return WebPage(
        children: [
          WebPanel(
            child: EmptyState(
              icon: Icons.groups_2_outlined,
              title: subs.isTrial
                  ? 'Referidos no disponibles en la prueba'
                  : 'Gana dinero con tus referidos',
              message:
                  'Con un plan pagado obtienes tu código de referido y ganas comisión cada vez que un amigo compre un plan con él.',
              action: GoldButton(
                label: 'Ver planes',
                expand: false,
                onPressed: onOpenPlans,
              ),
            ),
          ),
        ],
      );
    }

    final hero = WebPanel(
      highlight: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Disponible para retiro', style: WebPalette.body(13.5)),
              const SizedBox(height: 6),
              Text(
                fmtCop(refs.availableCop),
                style: WebPalette.display(40, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                refs.canWithdraw
                    ? 'Ya puedes solicitar tu retiro.'
                    : 'Podrás retirar al acumular ${fmtCop(100000)} disponibles.',
                style: WebPalette.body(13.5),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 260,
                child: GoldButton(
                  label: 'Solicitar retiro',
                  icon: Icons.account_balance_wallet_outlined,
                  onPressed: refs.canWithdraw ? () => _withdraw(context) : null,
                ),
              ),
            ],
          );
          final codeBox = (code ?? '').isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Comparte tu código',
                      style: WebPalette.display(16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tus amigos deben escribirlo al registrarse.',
                      style: WebPalette.body(13),
                    ),
                    const SizedBox(height: 12),
                    ReferralCodeBox(code: code!),
                  ],
                );
          if (c.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 22), codeBox],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 24),
              SizedBox(width: 340, child: codeBox),
            ],
          );
        },
      ),
    );

    return WebPage(
      children: [
        hero,
        const SizedBox(height: 22),
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            StatTile(
              label: 'Referidos',
              value: '${refs.total}',
              icon: Icons.groups_2_outlined,
            ),
            StatTile(
              label: 'Activos',
              value: '${refs.activos}',
              icon: Icons.verified_outlined,
              color: WebPalette.emerald,
            ),
            StatTile(
              label: 'Retenido (3 días)',
              value: fmtCop(refs.pendingCop),
              icon: Icons.hourglass_top_rounded,
              color: WebPalette.amber,
            ),
            StatTile(
              label: 'En retiro',
              value: fmtCop(refs.inWithdrawalCop),
              icon: Icons.sync_alt_rounded,
              color: WebPalette.violet,
            ),
            StatTile(
              label: 'Pagado',
              value: fmtCop(refs.paidCop),
              icon: Icons.payments_outlined,
              color: WebPalette.emerald,
            ),
          ],
        ),
        const SizedBox(height: 22),
        WebPanel(
          title: 'Personas que invitaste',
          subtitle: 'Se activan cuando compran un plan con tu código',
          icon: Icons.person_add_alt_1_outlined,
          actions: [
            WebIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Actualizar',
              onPressed: refs.loading ? null : () => refs.load(refresh: true),
            ),
          ],
          child: refs.loading && refs.items.isEmpty
              ? const TableSkeleton(rows: 4)
              : refs.items.isEmpty
              ? const EmptyState(
                  icon: Icons.group_add_outlined,
                  title: 'Aún no tienes referidos',
                  message:
                      'Comparte tu código con tus amigos para empezar a ganar.',
                )
              : WebTable<ReferralItem>(
                  rows: refs.items,
                  mobileTitle: (r) => Text(
                    r.referredName ?? 'Usuario',
                    style: WebPalette.display(15, weight: FontWeight.w700),
                  ),
                  columns: [
                    WebColumn(
                      'Nombre',
                      (r) =>
                          CellText(r.referredName ?? 'Usuario', strong: true),
                      flex: 3,
                    ),
                    WebColumn(
                      'Correo',
                      (r) => CellText(r.referredEmail ?? ''),
                      flex: 3,
                    ),
                    WebColumn(
                      'Registro',
                      (r) => CellText(_fmtDate(r.createdAt)),
                      flex: 2,
                    ),
                    WebColumn(
                      'Estado',
                      (r) => r.proActive
                          ? const StatusChip(
                              label: 'Plan activo',
                              color: WebPalette.emerald,
                            )
                          : const StatusChip(
                              label: 'Sin plan',
                              color: WebPalette.textFaint,
                            ),
                      flex: 2,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        const _HowItWorks(),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        Icons.share_outlined,
        'Comparte tu código',
        'Tus amigos lo escriben al registrarse.',
      ),
      (
        Icons.shopping_bag_outlined,
        'Ellos compran un plan',
        'Ganas comisión por cada compra con tu código.',
      ),
      (
        Icons.lock_clock_outlined,
        'Retención de 3 días',
        'Luego la comisión pasa a "Disponible".',
      ),
      (
        Icons.account_balance_outlined,
        'Retira tu dinero',
        'Desde ${fmtCop(100000)} a tu banco o billetera.',
      ),
    ];
    return WebPanel(
      title: '¿Cómo funciona?',
      icon: Icons.lightbulb_outline_rounded,
      child: ResponsiveGrid(
        minItemWidth: 220,
        children: [
          for (var i = 0; i < steps.length; i++)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(color: WebPalette.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: WebPalette.goldGradient,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: WebPalette.body(
                            13,
                            weight: FontWeight.w800,
                            color: const Color(0xFF1A1300),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(steps[i].$1, color: WebPalette.goldLight, size: 22),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    steps[i].$2,
                    style: WebPalette.body(
                      15,
                      weight: FontWeight.w700,
                      color: WebPalette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(steps[i].$3, style: WebPalette.body(13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
