import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:base_app/presentation/widgets/referrals/referral_kpis.dart';

class ReferralsTab extends StatelessWidget {
  const ReferralsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReferralProvider>(
      builder: (_, p, __) {
        if (p.loading && p.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () => p.load(refresh: true),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              // 👇 NUEVO: Tarjeta que pinta la comisión disponible del provider
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Comisión disponible',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        // p.availableCop lo provee el Provider
                        '\$${p.availableCop.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // KPIs existentes (cuentas)
              ReferralKpis(
                total: p.total,
                activos: p.activos,
                inactivos: p.inactivos,
                comisionPendiente: p.payoutPending,
                comisionPagada: p.payoutPaid,
                moneda: p.payoutCurrency,
              ),

              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Últimos referidos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              if (p.items.isEmpty && !p.loading) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Text(
                    'Aún no tienes referidos.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                  ),
                ),
              ] else ...[
                ...p.items.map(
                  (e) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(e.referredName ?? e.referredEmail ?? 'Usuario'),
                    subtitle: Text(
                      'Estado: ${_humanStatus(e.status)} • ${_fmt(e.createdAt)}',
                    ),
                    trailing: _ProBadgeMini(active: e.proActive),
                  ),
                ),
              ],

              if (p.loading) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _humanStatus(String raw) {
    switch (raw) {
      case 'converted':
        return 'Convertido';
      case 'registered':
        return 'Registrado';
      case 'pending':
        return 'Pendiente';
      case 'blocked':
        return 'Bloqueado';
      case 'spam':
        return 'Spam';
      default:
        return raw;
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _ProBadgeMini extends StatelessWidget {
  final bool active;
  const _ProBadgeMini({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.green : Colors.grey;
    final text = active ? 'PRO' : 'No PRO';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }
}
