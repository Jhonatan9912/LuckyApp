// lib/presentation/screens/admin_dashboard/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'logic/admin_dashboard_controller.dart';
import 'widgets/kpi_grid.dart';
import 'widgets/loans_by_month_chart.dart';
import 'package:base_app/data/session/session_manager.dart';
import '../login/login_screen.dart';
import '../dashboard/widgets/help_bottom_sheet.dart';
import 'widgets/users_bottom_sheet.dart';
import 'widgets/games_bottom_sheet.dart'; // 👈 NUEVO: import del sheet de Juegos
import 'widgets/players_bottom_sheet.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminDashboardController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = AdminDashboardController();
    _guardAndLoad();
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

  void _openUsersSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UsersBottomSheet(
        loader: () async {
          final list = await ctrl.loadAllUsers();
          return list
              .map(
                (m) => UserRow(
                  id: int.tryParse(m['id'] ?? '') ?? 0,
                  name: m['name'] ?? '',
                  phone: m['phone'] ?? '',
                  role: m['role'] ?? '',
                  roleId: int.tryParse(m['role_id'] ?? '') ?? 0,
                  code: m['public_code'] ?? m['code'] ?? '',
                ),
              )
              .toList();
        },
        onUpdateRole: (userId, newRoleId) async {
          final m = await ctrl.updateUserRole(userId, newRoleId);

          int toInt(dynamic v) {
            if (v == null) return 0;
            if (v is num) return v.toInt();
            if (v is String) return int.tryParse(v) ?? 0;
            return 0;
          }

          String toStr(dynamic v) => v?.toString() ?? '';

          return UserRow(
            id: toInt(m['id']),
            name: toStr(m['name']),
            phone: toStr(m['phone']),
            code: toStr(m['public_code'] ?? m['code']),
            roleId: toInt(m['role_id']),
            role: toStr(m['role']),
          );
        },
        onDelete: (userId) => ctrl.deleteUser(userId),
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
                  winningNumber: (m['winning_number'] == null)
                      ? null
                      : toInt(m['winning_number']),
                  stateId: (m['state_id'] == null)
                      ? null
                      : toInt(m['state_id']),
                ),
              )
              .toList();
        },
        loadLotteries: ctrl.loadLotteries,
        countLoader: ({String q = ''}) => ctrl.countAllGames(q: q),
        onDelete: (gameId) => ctrl.deleteGame(gameId),
        onSetWinner: (id, n) => ctrl.setGameWinner(id, n),
        onUpdate: (id, input) => ctrl.updateGame(id, input), // 👈 AGREGA ESTO
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
        loader: ({String q = ''}) async {
          final list = await ctrl.loadAllPlayers(q: q);
          return list.map<PlayerRow>((m) {
            String to3(dynamic e) {
              final s = e.toString();
              final neg = s.startsWith('-');
              final core = neg ? s.substring(1) : s;
              final padded = core.padLeft(3, '0');
              return neg ? '-$padded' : padded;
            }

            final nums = (m['numbers'] as List? ?? const []).map(to3).toList();

            return PlayerRow(
              id: (m['user_id'] as num).toInt(),
              name: (m['player_name'] ?? '').toString(),
              code: (m['code'] ?? m['public_code'] ?? '').toString(),
              gameId: (m['game_id'] as num).toInt(),
              lotteryName: (m['lottery_name'] ?? '').toString(),
              playedDate: (m['played_date'] ?? '').toString(),
              playedTime: (m['played_time'] ?? '').toString(),
              numbers: nums,
            );
          }).toList();
        },
        countLoader: ({String q = ''}) => ctrl.countAllPlayers(q: q),

        // 👇 IMPORTANTE: habilita el lápiz
        onUpdateNumbers: (userId, gameId, numbers) => ctrl.updatePlayerNumbers(
          userId: userId,
          gameId: gameId,
          numbers: numbers,
        ),

        // eliminar (ya lo tenías)
        onDelete: (userId, gameId) =>
            ctrl.deletePlayerNumbers(userId: userId, gameId: gameId),

        // opcional: si no usas abrir detalle, déjalo null
        onOpen: null,
      ),
    );

    await ctrl.load();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[screen] build() kpis=${ctrl.kpis}');
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Tablero', style: TextStyle(color: Colors.orange[800])),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        actionsIconTheme: const IconThemeData(color: Colors.deepPurple),
        leading: IconButton(
          tooltip: 'Preguntas frecuentes',
          icon: const Icon(Icons.help_outline),
          onPressed: _openFaq,
        ),
        actions: [
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
                colors: [Color(0xFFFFF5E6), Color(0xFFFFF0D6)],
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

                return RefreshIndicator(
                  onRefresh: () async => ctrl.load(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KpiGrid(
                          kpis: ctrl.kpis!,
                          onUsersTap: _openUsersSheet,
                          onGamesTap: _openGamesSheet,
                          onPlayersTap:
                              _openPlayersSheet, // 👈 pasar el callback aquí
                        ),
                        const SizedBox(height: 16),
                        LoansByMonthChart(data: ctrl.loansByMonth),
                        const SizedBox(height: 32),
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
}
