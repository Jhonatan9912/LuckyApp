// lib/web/player/player_plan_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:base_app/presentation/providers/subscription_provider.dart';

import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import '../widgets/web_ui.dart';

const _playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.tuempresa.base_app';
const _advisorPhone = '573218597037';

class _Plan {
  final String name;
  final int digits;
  final int price;
  final List<String> perks;
  final bool featured;
  const _Plan(
    this.name,
    this.digits,
    this.price,
    this.perks, {
    this.featured = false,
  });
}

const _plans = [
  _Plan('Starter', 2, 10000, [
    'Juega con 2 cifras',
    'Reserva tus números',
    'Historial y resultados',
  ]),
  _Plan('Lite', 3, 20000, [
    'Juega con 2 y 3 cifras',
    'Reserva tus números',
    'Comisión por referidos',
  ]),
  _Plan('Completa', 4, 60000, [
    'Juega con 2, 3 y 4 cifras',
    'Notificaciones de premio',
    'Comisión por referidos',
  ], featured: true),
  _Plan('Quinta', 5, 100000, [
    'Todas las modalidades',
    'Incluye Quinta (5 cifras)',
    'Comisión por referidos',
  ]),
];

class PlayerPlanPage extends StatelessWidget {
  const PlayerPlanPage({super.key});

  String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _askAdvisor(String plan) {
    final text = Uri.encodeComponent(
      'Hola, quiero activar el plan $plan de CM APP.',
    );
    launchUrl(
      Uri.parse('https://wa.me/$_advisorPhone?text=$text'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionProvider>();
    final pro = subs.isPremium;
    final maxD = subs.maxDigits ?? 0;

    return WebPage(
      children: [
        WebPanel(
          highlight: pro,
          child: Wrap(
            spacing: 24,
            runSpacing: 18,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusChip(
                    label: pro
                        ? (subs.isTrial ? 'PRUEBA GRATUITA' : 'PLAN ACTIVO')
                        : 'SIN PLAN',
                    color: pro ? WebPalette.emerald : WebPalette.textFaint,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    pro
                        ? 'Juegas hasta ${maxD == 5 ? 'Quinta (5 cifras)' : '$maxD cifras'}'
                        : 'Activa un plan y empieza a reservar',
                    style: WebPalette.display(26, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pro
                        ? 'Desde ${_fmt(subs.since)} · Vence ${_fmt(subs.expiresAt)}'
                        : 'Elige la modalidad que prefieras. Puedes cambiar de plan cuando quieras.',
                    style: WebPalette.body(14),
                  ),
                ],
              ),
              GhostButton(
                label: 'Actualizar estado',
                icon: Icons.refresh_rounded,
                onPressed: () => subs.refresh(force: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Planes disponibles',
          style: WebPalette.display(20, weight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Pago mensual. La compra se realiza desde la app de Android o con un asesor.',
          style: WebPalette.body(14),
        ),
        const SizedBox(height: 18),
        ResponsiveGrid(
          minItemWidth: 250,
          children: [
            for (final p in _plans)
              _PlanCard(
                plan: p,
                current: pro && !subs.isTrial && maxD == p.digits,
                onAdvisor: () => _askAdvisor(p.name),
              ),
          ],
        ),
        const SizedBox(height: 22),
        WebPanel(
          icon: Icons.phone_android_rounded,
          title: '¿Prefieres comprar desde el celular?',
          subtitle:
              'Tu plan se activa automáticamente en la web con la misma cuenta.',
          actions: [
            GhostButton(
              label: 'Abrir Google Play',
              icon: Icons.shop_outlined,
              onPressed: () => launchUrl(
                Uri.parse(_playStoreUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _PlanCard extends StatefulWidget {
  final _Plan plan;
  final bool current;
  final VoidCallback onAdvisor;
  const _PlanCard({
    required this.plan,
    required this.current,
    required this.onAdvisor,
  });

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final featured = p.featured;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: featured
                ? [
                    WebPalette.gold.withValues(alpha: 0.20),
                    Colors.white.withValues(alpha: 0.03),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.white.withValues(alpha: 0.02),
                  ],
          ),
          border: Border.all(
            color: featured || widget.current
                ? WebPalette.gold.withValues(alpha: 0.55)
                : (_hover
                      ? WebPalette.gold.withValues(alpha: 0.3)
                      : WebPalette.glassBorder),
            width: featured ? 1.4 : 1,
          ),
          boxShadow: [
            if (featured || _hover)
              BoxShadow(
                color: WebPalette.gold.withValues(
                  alpha: featured ? 0.15 : 0.08,
                ),
                blurRadius: 40,
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  p.name,
                  style: WebPalette.display(20, weight: FontWeight.w800),
                ),
                const Spacer(),
                if (widget.current)
                  const StatusChip(label: 'Tu plan', color: WebPalette.emerald)
                else if (featured)
                  const StatusChip(
                    label: 'Popular',
                    color: WebPalette.goldLight,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p.digits == 5 ? 'Quinta · 5 cifras' : '${p.digits} cifras',
              style: WebPalette.body(13.5),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmtCop(p.price),
                  style: WebPalette.display(30, weight: FontWeight.w800),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('/ mes', style: WebPalette.body(13)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final perk in p.perks)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: WebPalette.goldLight,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        perk,
                        style: WebPalette.body(14, color: WebPalette.text),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            if (featured)
              GoldButton(label: 'Quiero este plan', onPressed: widget.onAdvisor)
            else
              SizedBox(
                width: double.infinity,
                child: GhostButton(
                  label: 'Quiero este plan',
                  onPressed: widget.onAdvisor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
