import 'package:flutter/material.dart';
import 'kpi_card.dart';

class KpiGrid extends StatelessWidget {
  final Map<String, dynamic> kpis;
  final VoidCallback? onUsersTap;
  final VoidCallback? onGamesTap;
  final VoidCallback? onPlayersTap;
  
  const KpiGrid({
    super.key,
    required this.kpis,
    this.onUsersTap,
    this.onGamesTap,
    this.onPlayersTap,
  });

  @override
  Widget build(BuildContext context) {
    final users = (kpis['users'] ?? kpis['total_users'] ?? kpis['usuarios'] ?? 0).toString();
    final games = (kpis['games'] ?? kpis['total_games'] ?? kpis['juegos'] ?? 0).toString();
    final players = (kpis['players'] ?? kpis['total_players'] ?? kpis['jugadores'] ?? 0).toString(); // 👈 NUEVO

    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = constraints.maxWidth < 360 ? 1.4 : 1.8;
        return GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: aspect,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            KpiCard(
              title: 'Usuarios',
              value: users,
              icon: Icons.people_outline,
              onTap: onUsersTap,
            ),
            KpiCard(
              title: 'Juegos Activos',
              value: games,
              icon: Icons.casino_outlined,
              onTap: onGamesTap,
            ),
            KpiCard( // 👇 NUEVO
              title: 'Jugadores',
              value: players,
              icon: Icons.group_outlined,
              onTap: onPlayersTap,
            ),
          ],
        );
      },
    );
  }
}
