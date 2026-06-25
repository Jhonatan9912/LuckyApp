// lib/presentation/screens/admin_dashboard/admin_dashboard_screen.dart
import 'dart:io';                           // 👈 NUEVO
import 'package:http/http.dart' as http;   // 👈 NUEVO
import 'package:path_provider/path_provider.dart'; // 👈 NUEVO
import 'package:open_filex/open_filex.dart';     // ya lo tenías
import 'package:share_plus/share_plus.dart';     // 👈 NUEVO

import 'package:flutter/material.dart';
import 'logic/admin_dashboard_controller.dart';
import 'widgets/kpi_grid.dart';
import 'widgets/loans_by_month_chart.dart';
import 'package:base_app/data/session/session_manager.dart';
import '../login/login_screen.dart';
import '../dashboard/widgets/help_bottom_sheet.dart';
import 'widgets/users_bottom_sheet.dart';
import 'widgets/games_bottom_sheet.dart';
import 'widgets/players_bottom_sheet.dart';
import 'widgets/referrals_bottom_sheet.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/referrals_controller.dart';
import 'package:base_app/data/api/admin_referrals_api.dart';
import 'package:base_app/data/api/api_service.dart';
import 'package:open_filex/open_filex.dart'; 

enum _ReportAction { close, open, share }


class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminDashboardController ctrl;
  late final ReferralsController _refCtrl;

  @override
  void initState() {
    super.initState();
    ctrl = AdminDashboardController();

    _refCtrl = ReferralsController(
      api: AdminReferralsApi(baseUrl: ApiService.defaultBaseUrl),
    );
    _refCtrl.addListener(() {
      if (mounted) setState(() {});
    });

    _guardAndLoad();

    // 👇 carga las comisiones pendientes (para KPI de Referidos)
    _refCtrl.loadCommissions(status: 'requested');
  }

  Future<void> _guardAndLoad() async {
    final roleId = await SessionManager().getRoleId();
    if (roleId != 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solo administradores pueden ver este panel'),
          ),
        );
        Navigator.of(context).maybePop();
      }
      return;
    }
    await ctrl.load();
    if (mounted) setState(() {});
  }

  void _openFaq() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      builder: (_) => const HelpBottomSheet(),
    );
  }

  Future<void> _confirmAndLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await SessionManager().clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  /// 🔹 Descarga el CSV de juegos activos y ofrece abrirlo o compartirlo.
  Future<void> _downloadExcelReport() async {
    // 0) Confirmación previa
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descargar informe'),
        content: const Text(
          '¿Deseas descargar el informe de juegos activos y números reservados?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1) Token JWT (ajusta el método si se llama distinto)
      final token = await SessionManager().getToken();

      // 2) Base URL (sin /api)
      final base = ApiService.defaultBaseUrl; // ej: http://10.0.2.2:8000

      // 3) URL completa correcta (con /api/admin/...)
      final url = '$base/api/admin/dashboard/export-active-games';
      debugPrint('[admin/export] GET $url');

      final uri = Uri.parse(url);

      // 4) Petición HTTP
      final resp = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'text/csv',
        },
      );

      debugPrint(
        '[admin/export] status=${resp.statusCode} len=${resp.bodyBytes.length}',
      );

      if (resp.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Error al descargar informe (${resp.statusCode})'),
          ),
        );
        return;
      }

      // 5) Guardar archivo en documentos de la app
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/juegos_activos.csv');
      await file.writeAsBytes(resp.bodyBytes, flush: true);

      if (!mounted) return;

      // 6) Preguntar qué quiere hacer: abrir o compartir
      final action = await showDialog<_ReportAction>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Informe descargado'),
          content: Text(
            'El informe se guardó en:\n${file.path}\n\n¿Qué deseas hacer?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_ReportAction.close),
              child: const Text('Cerrar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_ReportAction.share),
              child: const Text('Compartir'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_ReportAction.open),
              child: const Text('Abrir'),
            ),
          ],
        ),
      );

      if (action == _ReportAction.open) {
        final result = await OpenFilex.open(file.path);
        debugPrint(
            '[admin/export] open result: ${result.type} - ${result.message}');

        if (result.type != ResultType.done) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo abrir el informe.\n'
                'Instala una app que pueda abrir archivos CSV (por ejemplo, Excel o Google Sheets).',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else if (action == _ReportAction.share) {
        try {
          await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Informe de juegos activos y números reservados',
          );
        } catch (e, st) {
          debugPrint('Error al compartir informe: $e\n$st');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo compartir el informe.'),
            ),
          );
        }
      }
    } catch (e, st) {
      debugPrint('Error descargando informe: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ocurrió un error al descargar el informe.'),
        ),
      );
    }
  }


  void _openUsersSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UsersBottomSheet(
        loader: () async {
          final list = await ctrl.loadAllUsers();
          debugPrint(
            '[users loader] first map: ${list.isNotEmpty ? list.first : 'empty'}',
          );
          return list.map<UserRow>((m) => UserRow.fromJson(m)).toList();
        },
        onUpdateRole: (userId, newRoleId) async {
          final m = await ctrl.updateUserRole(userId, newRoleId);
          try {
            return UserRow.fromJson(Map<String, dynamic>.from(m));
          } catch (_) {
            return null;
          }
        },
        onDelete: (userId) => ctrl.deleteUser(userId),
        // ⭐ NUEVO: activar PRO manualmente (30 días)
        onManualGrantPro: (userId, productId) async {
          final resp = await ctrl.manualGrantPro(
            userId: userId,
            productId: productId, // viene desde UsersBottomSheet
            days: 30,
          );
          return resp;
        },
      ),
    );

    // al cerrar el sheet, refresca KPIs
    await ctrl.load();
    if (mounted) setState(() {});
  }

  void _openGamesSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GamesBottomSheet(
        loader: ({String q = ''}) async {
          final list = await ctrl.loadAllGames(q: q);
          int toInt(dynamic v) {
            if (v == null) return 0;
            if (v is num) return v.toInt();
            if (v is String) return int.tryParse(v) ?? 0;
            return 0;
          }

          String toStr(dynamic v) => v?.toString() ?? '';
          return list
              .map(
                (m) => GameRow(
                  id: toInt(m['id']),
                  lotteryName: toStr(m['lottery_name']),
                  playedDate: toStr(m['played_date']),
                  playedTime: toStr(m['played_time']),
                  playersCount: toInt(m['players_count']),
                  winningNumber: m['winning_number'] == null
                      ? null
                      : toInt(m['winning_number']),
                  stateId:
                      m['state_id'] == null ? null : toInt(m['state_id']),
                  digits: toInt(m['digits'] ?? 3),
                ),
              )
              .toList();
        },
        loadLotteries: ctrl.loadLotteries,
        countLoader: ({String q = ''}) => ctrl.countAllGames(q: q),
        onDelete: (gameId) => ctrl.deleteGame(gameId),
        onSetWinner: (id, n) => ctrl.setGameWinner(id, n),
        onUpdate: (id, input) => ctrl.updateGame(id, input),
      ),
    );

    await ctrl.load();
    if (mounted) setState(() {});
  }

  void _openPlayersSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlayersBottomSheet(
        loader: ({String q = '', String state = 'active'}) async {
          final list = await ctrl.loadAllPlayers(q: q, state: state);
          return list.map<PlayerRow>((m) {
            final int playerDigits = (m['digits'] as num?)?.toInt() ?? 3;

            String toDigits(dynamic e) {
              final s = e.toString();
              final neg = s.startsWith('-');
              final core = neg ? s.substring(1) : s;
              final padded = core.padLeft(playerDigits, '0');
              return neg ? '-$padded' : padded;
            }

            final nums =
                (m['numbers'] as List? ?? const []).map(toDigits).toList();

            return PlayerRow(
              id: (m['user_id'] as num).toInt(),
              name: (m['player_name'] ?? '').toString(),
              code: (m['code'] ?? m['public_code'] ?? '').toString(),
              gameId: (m['game_id'] as num).toInt(),
              lotteryName: (m['lottery_name'] ?? '').toString(),
              playedDate: (m['played_date'] ?? '').toString(),
              playedTime: (m['played_time'] ?? '').toString(),
              numbers: nums,
              digits: playerDigits,
            );
          }).toList();
        },
        countLoader: ({String q = '', String state = 'active'}) =>
            ctrl.countAllPlayers(q: q, state: state),
        onUpdateNumbers: (userId, gameId, numbers) =>
            ctrl.updatePlayerNumbers(
                userId: userId, gameId: gameId, numbers: numbers),
        onDelete: (userId, gameId) =>
            ctrl.deletePlayerNumbers(userId: userId, gameId: gameId),
        onOpen: null,
      ),
    );

    await ctrl.load();
    if (mounted) setState(() {});
  }

  void _openReferralsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DefaultTabController(
        length: 3, // Resumen / Comisiones / Pagos
        child: ReferralsBottomSheet(
          onPaySelected: null,
          onOpenUser: null,
          onToggleSelectCommission: null,
          onMarkAsPaid: null,
        ),
      ),
    );
    await ctrl.load();
    await _refCtrl.loadCommissions(status: 'requested');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[screen] build() kpis=${ctrl.kpis}');
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFD4AF37), Color(0xFFF5C842), Color(0xFFD4AF37)],
          ).createShader(bounds),
          child: Text(
            'Tablero Admin',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFFD4AF37)),
        actionsIconTheme: const IconThemeData(color: Color(0xFFD4AF37)),
        leading: IconButton(
          tooltip: 'Preguntas frecuentes',
          icon: const Icon(Icons.help_outline),
          onPressed: _openFaq,
        ),
        actions: [
IconButton(
  tooltip: 'Exportar informe (Excel)',
  icon: const Icon(Icons.grid_on_outlined),
  onPressed: _downloadExcelReport,
),

          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _confirmAndLogout,
          ),
        ],

      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF9F0), Color(0xFFFFF3D8)],
              ),
            ),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (_, __) {
                if (ctrl.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (ctrl.error != null) {
                  return Center(child: Text('Error: ${ctrl.error}'));
                }
                if (ctrl.kpis == null) {
                  return const Center(child: Text('Sin datos'));
                }

                final mergedKpis = {
                  ...?ctrl.kpis,
                  'referrals': _refCtrl.pendingCommissionsCount,
                };

                return RefreshIndicator(
                  onRefresh: () async {
                    await Future.wait([
                      ctrl.load(),
                      _refCtrl.loadCommissions(status: 'requested'),
                    ]);
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Resumen general',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF4A3800),
                          ),
                        ),
                        const SizedBox(height: 8),
                        KpiGrid(
                          kpis: mergedKpis,
                          onUsersTap: _openUsersSheet,
                          onGamesTap: _openGamesSheet,
                          onPlayersTap: _openPlayersSheet,
                          onReferralsTap: _openReferralsSheet,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }
}
