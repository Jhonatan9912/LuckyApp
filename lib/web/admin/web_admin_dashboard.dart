// lib/web/admin/web_admin_dashboard.dart
//
// Panel web de administración. Usa los mismos controladores de la app
// (AdminDashboardController y ReferralsController); solo cambia la interfaz.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/core/utils/download/browser_download.dart';
import 'package:base_app/data/api/admin_referrals_api.dart';
import 'package:base_app/data/api/api_service.dart';
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/admin_dashboard_controller.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/referrals_controller.dart';

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';
import '../widgets/web_ui.dart';
import 'admin_games_page.dart';
import 'admin_players_page.dart';
import 'admin_referrals_page.dart';
import 'admin_users_page.dart';

enum _Section { overview, users, games, players, referrals }

class WebAdminDashboard extends StatefulWidget {
  const WebAdminDashboard({super.key});

  @override
  State<WebAdminDashboard> createState() => _WebAdminDashboardState();
}

class _WebAdminDashboardState extends State<WebAdminDashboard> {
  final _ctrl = AdminDashboardController();
  late final ReferralsController _refCtrl = ReferralsController(
    api: AdminReferralsApi(baseUrl: ApiService.defaultBaseUrl),
  );
  _Section _section = _Section.overview;
  String _userName = '';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _guardAndLoad();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardAndLoad() async {
    final session = SessionManager();
    if (await session.getRoleId() != 1) {
      // Sin rol admin: redirige en silencio al panel normal, sin revelar que
      // esta ruta es un panel de administración.
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/dashboard', (_) => false);
      }
      return;
    }
    await Future.wait([
      _ctrl.load(),
      _refCtrl.loadCommissions(status: 'requested'),
    ]);
    try {
      final token = await session.getToken();
      if (token != null && mounted) {
        final me = await context.read<AuthApi>().me(token);
        if (mounted) setState(() => _userName = (me['name'] ?? '').toString());
      }
    } catch (_) {}
  }

  Future<void> _export() async {
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: 'Descargar informe',
      message:
          '¿Descargar el informe de juegos activos y números reservados (CSV, compatible con Excel)?',
      okText: 'Descargar',
      icon: Icons.download_rounded,
    );
    if (!ok) return;
    setState(() => _exporting = true);
    try {
      final token = await SessionManager().getToken();
      final resp = await http.get(
        Uri.parse(
          '${ApiService.defaultBaseUrl}/api/admin/dashboard/export-active-games',
        ),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'text/csv'},
      );
      if (resp.statusCode != 200) {
        throw Exception('El servidor respondió ${resp.statusCode}');
      }
      downloadBytesInBrowser(
        resp.bodyBytes,
        fileName: 'juegos_activos.csv',
        mimeType: 'text/csv',
      );
      WebAlerts.toast(
        'Se descargó juegos_activos.csv',
        title: 'Informe listo',
        tone: AlertTone.success,
      );
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo descargar',
        message: '$e',
        tone: AlertTone.error,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _logout() async {
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: 'Cerrar sesión',
      message: '¿Seguro que quieres salir del panel?',
      okText: 'Salir',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await SessionManager().clear();
    nav.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  void _go(_Section s) {
    setState(() => _section = s);
    if (s == _Section.overview) {
      _ctrl.load();
      _refCtrl.loadCommissions(status: 'requested');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ctrl, _refCtrl]),
      builder: (context, _) {
        final pending = _refCtrl.pendingCommissionsCount;
        final (title, subtitle) = switch (_section) {
          _Section.overview => ('Resumen', 'Estado general de la plataforma'),
          _Section.users => ('Usuarios', 'Cuentas, roles y planes'),
          _Section.games => ('Juegos', 'Programación de sorteos y resultados'),
          _Section.players => ('Jugadores', 'Números reservados por juego'),
          _Section.referrals => (
            'Referidos y pagos',
            'Comisiones, retiros y comprobantes',
          ),
        };

        final body = switch (_section) {
          _Section.overview => _Overview(
            ctrl: _ctrl,
            refCtrl: _refCtrl,
            onGo: _go,
            onExport: _export,
          ),
          _Section.users => AdminUsersPage(ctrl: _ctrl),
          _Section.games => AdminGamesPage(ctrl: _ctrl),
          _Section.players => AdminPlayersPage(ctrl: _ctrl),
          _Section.referrals => AdminReferralsPage(ctrl: _refCtrl),
        };

        return WebShellLayout(
          items: [
            const WebNavItem(Icons.space_dashboard_outlined, 'Resumen'),
            const WebNavItem(Icons.people_alt_outlined, 'Usuarios'),
            const WebNavItem(Icons.casino_outlined, 'Juegos'),
            const WebNavItem(Icons.sports_esports_outlined, 'Jugadores'),
            WebNavItem(
              Icons.payments_outlined,
              'Referidos y pagos',
              badge: pending,
            ),
          ],
          selected: _section.index,
          onSelect: (i) => _go(_Section.values[i]),
          title: title,
          subtitle: subtitle,
          userName: _userName,
          userRole: 'Administrador',
          onLogout: _logout,
          actions: [
            WebIconButton(
              icon: _exporting
                  ? Icons.hourglass_top_rounded
                  : Icons.file_download_outlined,
              tooltip: 'Exportar informe (Excel)',
              onPressed: _exporting ? null : _export,
            ),
          ],
          body: body,
        );
      },
    );
  }
}

class _Overview extends StatelessWidget {
  final AdminDashboardController ctrl;
  final ReferralsController refCtrl;
  final ValueChanged<_Section> onGo;
  final VoidCallback onExport;

  const _Overview({
    required this.ctrl,
    required this.refCtrl,
    required this.onGo,
    required this.onExport,
  });

  String _k(List<String> keys) {
    final k = ctrl.kpis ?? const {};
    for (final key in keys) {
      if (k[key] != null) return '${k[key]}';
    }
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    if (ctrl.loading && ctrl.kpis == null) {
      return const WebPage(children: [TableSkeleton(rows: 5)]);
    }
    if (ctrl.error != null && ctrl.kpis == null) {
      return WebPage(
        children: [
          WebPanel(
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No se pudo cargar el resumen',
              message: ctrl.error,
              action: GoldButton(
                label: 'Reintentar',
                expand: false,
                onPressed: ctrl.load,
              ),
            ),
          ),
        ],
      );
    }

    final requests = refCtrl.commissions.take(5).toList();

    return WebPage(
      children: [
        _Welcome(onExport: onExport, onGames: () => onGo(_Section.games)),
        const SizedBox(height: 22),
        ResponsiveGrid(
          minItemWidth: 220,
          children: [
            StatTile(
              label: 'Usuarios',
              value: _k(['users', 'total_users', 'usuarios']),
              icon: Icons.people_alt_outlined,
              onTap: () => onGo(_Section.users),
            ),
            StatTile(
              label: 'Juegos',
              value: _k(['games', 'total_games', 'juegos']),
              icon: Icons.casino_outlined,
              color: WebPalette.violet,
              onTap: () => onGo(_Section.games),
            ),
            StatTile(
              label: 'Jugadores',
              value: _k(['players', 'total_players', 'jugadores']),
              icon: Icons.sports_esports_outlined,
              color: WebPalette.emerald,
              onTap: () => onGo(_Section.players),
            ),
            StatTile(
              label: 'Retiros pendientes',
              value: '${refCtrl.pendingCommissionsCount}',
              icon: Icons.pending_actions_outlined,
              color: WebPalette.amber,
              onTap: () => onGo(_Section.referrals),
            ),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, c) {
            final quick = WebPanel(
              title: 'Acciones rápidas',
              icon: Icons.bolt_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _QuickAction(
                    Icons.event_available_rounded,
                    'Programar un sorteo',
                    'Lotería, fecha y hora',
                    () => onGo(_Section.games),
                  ),
                  _QuickAction(
                    Icons.emoji_events_outlined,
                    'Publicar ganador',
                    'Notifica a los jugadores',
                    () => onGo(_Section.games),
                  ),
                  _QuickAction(
                    Icons.workspace_premium_outlined,
                    'Activar plan a un usuario',
                    'Pago por fuera de Play',
                    () => onGo(_Section.users),
                  ),
                  _QuickAction(
                    Icons.file_download_outlined,
                    'Exportar informe',
                    'Juegos activos y números (CSV)',
                    onExport,
                  ),
                ],
              ),
            );
            final pendingPanel = WebPanel(
              title: 'Retiros por pagar',
              subtitle: 'Últimas solicitudes de los usuarios',
              icon: Icons.request_page_outlined,
              actions: [
                TextButton(
                  onPressed: () => onGo(_Section.referrals),
                  child: const Text('Ver todas'),
                ),
              ],
              child: requests.isEmpty
                  ? const EmptyState(
                      icon: Icons.task_alt_rounded,
                      title: 'Todo al día',
                      message: 'No hay retiros pendientes.',
                    )
                  : Column(
                      children: [
                        for (final r in requests)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: WebPalette.amber.withValues(
                                      alpha: 0.14,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 18,
                                    color: WebPalette.amber,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CellText(r.userName, strong: true),
                                ),
                                Text(
                                  fmtCop(r.amountCop),
                                  style: WebPalette.display(
                                    14,
                                    weight: FontWeight.w700,
                                    color: WebPalette.goldLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            );
            if (c.maxWidth < 900) {
              return Column(
                children: [quick, const SizedBox(height: 18), pendingPanel],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: quick),
                const SizedBox(width: 18),
                Expanded(child: pendingPanel),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  final VoidCallback onExport;
  final VoidCallback onGames;
  const _Welcome({required this.onExport, required this.onGames});

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final greet = h < 12
        ? 'Buenos días'
        : (h < 19 ? 'Buenas tardes' : 'Buenas noches');
    return WebPanel(
      highlight: true,
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$greet 👋',
                style: WebPalette.display(26, weight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Esto es lo que está pasando hoy en CM APP.',
                style: WebPalette.body(14.5),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              GhostButton(
                label: 'Exportar',
                icon: Icons.file_download_outlined,
                onPressed: onExport,
              ),
              GoldButton(
                label: 'Gestionar juegos',
                icon: Icons.arrow_forward_rounded,
                expand: false,
                onPressed: onGames,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.title, this.subtitle, this.onTap);

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: _hover ? 0.07 : 0.03),
            border: Border.all(
              color: _hover
                  ? WebPalette.gold.withValues(alpha: 0.4)
                  : WebPalette.glassBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: WebPalette.goldLight, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: WebPalette.body(
                        14.5,
                        weight: FontWeight.w700,
                        color: WebPalette.text,
                      ),
                    ),
                    Text(widget.subtitle, style: WebPalette.body(12.5)),
                  ],
                ),
              ),
              AnimatedSlide(
                offset: Offset(_hover ? 0.2 : 0, 0),
                duration: const Duration(milliseconds: 160),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: WebPalette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
