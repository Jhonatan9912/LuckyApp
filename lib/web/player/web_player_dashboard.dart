// lib/web/player/web_player_dashboard.dart
//
// Panel web del jugador. Usa el mismo DashboardController y providers de la
// app (misma lógica y backend); solo cambia la interfaz.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:base_app/core/config/env.dart';
import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/data/api/games_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/domain/auth/auth_repository.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';
import 'package:base_app/presentation/screens/dashboard/controller/dashboard_controller.dart';
import 'package:base_app/presentation/screens/legal/account_privacy_screen.dart';

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/ball_reveal_overlay.dart';
import '../widgets/web_ui.dart';
import 'player_help_page.dart';
import 'player_history_page.dart';
import 'player_plan_page.dart';
import 'player_play_page.dart';
import 'player_referrals_page.dart';

enum _Section { play, history, referrals, plan, help }

class WebPlayerDashboard extends StatefulWidget {
  const WebPlayerDashboard({super.key});

  @override
  State<WebPlayerDashboard> createState() => _WebPlayerDashboardState();
}

class _WebPlayerDashboardState extends State<WebPlayerDashboard> {
  late final DashboardController _ctrl;
  _Section _section = _Section.play;
  bool _hydrating = true;
  bool _dialogBusy = false;
  bool _scheduleShownOnce = false;
  Timer? _notifTimer;
  VoidCallback? _subsListener;
  SubscriptionProvider? _subs;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    final session = SessionManager();
    final authApi = AuthApi(baseUrl: Env.apiBaseUrl);
    _ctrl = DashboardController(
      gamesApi: GamesApi(baseUrl: Env.apiBaseUrl),
      authRepo: AuthRepository(api: authApi, session: session),
      session: session,
      devUserId: 8,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final subs = _subs = context.read<SubscriptionProvider>();
      _subsListener = () => _ctrl.applyPremiumFromStore(
        premium: subs.isPremium,
        planDigits: subs.maxDigits ?? 3,
      );
      subs.addListener(_subsListener!);
      _subsListener!();
      unawaited(_loadUserName());
      await _hydrate();
    });
  }

  Future<void> _loadUserName() async {
    try {
      final token = await SessionManager().getToken();
      if (token == null || !mounted) return;
      final me = await context.read<AuthApi>().me(token);
      if (mounted) setState(() => _userName = (me['name'] ?? '').toString());
    } catch (_) {}
  }

  Future<void> _hydrate() async {
    await _ctrl.initSession();
    if (!mounted) return;
    if (!_ctrl.sessionReady) {
      // Sin sesión no se muestra el panel: siempre al login.
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      return;
    }
    await _ctrl.loadHistory();
    _ctrl.resetToInitial();
    if (mounted) setState(() => _hydrating = false);

    if (!mounted) return;
    final subs = context.read<SubscriptionProvider>();
    final refs = context.read<ReferralProvider>();
    unawaited(subs.refresh(force: true));
    unawaited(refs.load(refresh: true));
    unawaited(_ctrl.loadReferralCode());

    await _safeShow(_checkScheduleNotice);
    await _ctrl.loadNotifications();
    await _safeShow(_checkWinnerNotifications);

    if (!mounted) return;
    _notifTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _dialogBusy) return;
      await _ctrl.loadNotifications();
      await _safeShow(_checkWinnerNotifications);
      if (!_scheduleShownOnce) await _safeShow(_checkScheduleNotice);
    });
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    if (_subsListener != null) _subs?.removeListener(_subsListener!);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _safeShow(Future<void> Function() task) async {
    if (!mounted || _dialogBusy) return;
    _dialogBusy = true;
    try {
      await task();
    } finally {
      _dialogBusy = false;
    }
  }

  // ───────────────────────── Juego ─────────────────────────

  Future<void> _onDigitsChanged(int value) async {
    if (_ctrl.digitsPerBall == value) return;
    if (value >= 4) {
      final maxDigits = context.read<SubscriptionProvider>().maxDigits ?? 0;
      if (value > maxDigits) {
        WebAlerts.toast(
          'Esta modalidad requiere un plan superior.',
          title: 'Modalidad bloqueada',
          tone: AlertTone.warning,
        );
        setState(() => _section = _Section.plan);
        return;
      }
    }
    _ctrl.setDigitsPerBall(value);
    setState(() => _hydrating = true);
    await _ctrl.loadHistory();
    await _ctrl.restoreSelectionIfAny();
    if (mounted) setState(() => _hydrating = false);
  }

  Future<void> _play() async {
    if (!_ctrl.animating && !_ctrl.saving) await _ctrl.generateLocalPreview();
  }

  Future<void> _reserve() async {
    final out = await _ctrl.add();
    if (!mounted) return;

    if (out.ok) {
      if (out.code == 'REPLACED' && out.message != null) {
        WebAlerts.toast(
          out.message!,
          title: 'Información',
          tone: AlertTone.info,
        );
        return;
      }
      final formatted = _ctrl.numbers
          .map((n) => formatGameNumber(n, _ctrl.digitsPerBall))
          .join(' · ');
      WebAlerts.toast(
        out.gameCompleted
            ? 'Tus números: $formatted. El juego se completó y se abrió uno nuevo automáticamente.'
            : 'Tus números: $formatted',
        title: '¡Reserva confirmada!',
        tone: AlertTone.success,
      );
      if (out.gameCompleted) {
        _ctrl.resetToInitial();
        setState(() {});
      }
      return;
    }

    final code = out.code ?? '';
    final msg = out.message ?? 'No se pudo guardar la selección.';
    if (code == 'CONFLICT' || code == 'GAME_SWITCHED') {
      WebAlerts.toast(msg, title: 'Aviso', tone: AlertTone.warning);
      _ctrl.resetToInitial();
      setState(() {});
      await _ctrl.openFreshGame();
    } else if (code == 'UNAUTHORIZED' ||
        code == 'UNAUTHENTICATED' ||
        code == 'TOKEN_EXPIRED') {
      final nav = Navigator.of(context, rootNavigator: true);
      await WebAlerts.dialog(
        title: 'Sesión vencida',
        message: msg,
        tone: AlertTone.error,
      );
      nav.pushNamedAndRemoveUntil('/login', (_) => false);
    } else {
      await WebAlerts.dialog(
        title: 'No se pudo reservar',
        message: msg,
        tone: AlertTone.error,
      );
    }
  }

  bool _isCurrentGameClosed() {
    final gid = _ctrl.gameId;
    if (gid == null) return false;
    for (final m in _ctrl.history) {
      if ((m['game_id'] as num?)?.toInt() != gid) continue;
      final status = (m['status'] ?? m['result'] ?? '')
          .toString()
          .toLowerCase();
      return m['winning_number'] != null ||
          status.contains('closed') ||
          status.contains('completed') ||
          status.contains('perdido') ||
          status.contains('ganado');
    }
    return false;
  }

  // ───────────────────────── Notificaciones ─────────────────────────

  Future<void> _checkWinnerNotifications() async {
    final notifs = await _ctrl.fetchWinnerNotificationsOnce();
    if (!mounted || notifs.isEmpty) return;

    for (final n in notifs) {
      if (!mounted) return;
      final gameId = n['game_id'];
      final raw = (n['winning_number'] ?? '').toString();
      var digits = (n['digits'] as int?) ?? 0;
      if (digits == 0) {
        final len = raw.replaceAll('-', '').length;
        digits = len >= 5 ? 5 : (len == 4 ? 4 : (len <= 2 ? 2 : 3));
      }
      final numStr = formatGameNumber(
        int.tryParse(raw.replaceAll('-', '')) ?? 0,
        digits,
      );

      if ((n['kind'] ?? '').toString() == 'you_won') {
        await WebAlerts.dialog(
          title: '¡Ganaste el juego #$gameId!',
          message: 'Tu número ganador es $numStr. ¡Felicidades!',
          tone: AlertTone.success,
          okText: '¡Genial!',
          icon: Icons.emoji_events_rounded,
        );
      } else {
        WebAlerts.toast(
          'El número ganador es $numStr',
          title: 'Resultado del juego #$gameId',
          tone: AlertTone.info,
        );
      }
      if (mounted) {
        _ctrl.resetToInitial();
        setState(() {});
      }
    }
  }

  Future<void> _checkScheduleNotice() async {
    var item = await _ctrl.fetchScheduleFromListOnce();
    item ??= await _ctrl.peekScheduleOnce();
    if (!mounted || item == null) return;

    final key = [
      item['id'] ?? '',
      item['game_id'] ?? '',
      item['scheduled_at'] ?? item['when'] ?? '',
      item['title'] ?? '',
      item['body'] ?? '',
    ].join('|');

    final prefs = await SharedPreferences.getInstance();
    final nid = int.tryParse((item['id'] ?? '').toString());
    if (prefs.getString('last_schedule_key') == key) {
      _scheduleShownOnce = true;
      if (nid != null) await _ctrl.markReadIds([nid]);
      return;
    }

    WebAlerts.toast(
      (item['body'] ?? '').toString(),
      title: (item['title'] ?? '¡Juego programado!').toString(),
      tone: AlertTone.info,
    );
    _scheduleShownOnce = true;
    await prefs.setString('last_schedule_key', key);
    if (nid != null) await _ctrl.markReadIds([nid]);
  }

  Future<void> _openNotifications() async {
    _dialogBusy = true;
    try {
      await _ctrl.loadNotifications();
      await _ctrl.markUnreadAsRead();
      if (!mounted) return;
      await showWebSidePanel(
        context,
        title: 'Notificaciones',
        builder: (_) => _NotificationsList(items: _ctrl.notifications),
      );
    } finally {
      _dialogBusy = false;
    }
  }

  // ───────────────────────── Sesión ─────────────────────────

  Future<void> _logout() async {
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: 'Cerrar sesión',
      message: '¿Seguro que deseas salir de tu cuenta?',
      okText: 'Cerrar sesión',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    final subs = context.read<SubscriptionProvider>();
    _notifTimer?.cancel();
    try {
      subs.clear();
      await _ctrl.logout();
    } catch (e) {
      WebAlerts.toast('No se pudo cerrar sesión: $e', tone: AlertTone.error);
      return;
    }
    nav.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final subs = context.watch<SubscriptionProvider>();
        final historyUnlocked =
            subs.isPremium && (subs.maxDigits ?? 0) >= _ctrl.digitsPerBall;
        final unread = _ctrl.unreadCount;

        final (title, subtitle) = switch (_section) {
          _Section.play => (
            'Jugar',
            'Genera tus números y resérvalos para el próximo sorteo',
          ),
          _Section.history => ('Historial', 'Tus juegos, resultados y premios'),
          _Section.referrals => (
            'Referidos',
            'Invita amigos y gana comisiones',
          ),
          _Section.plan => ('Mi plan', 'Tu suscripción y planes disponibles'),
          _Section.help => ('Ayuda', 'Guías y preguntas frecuentes'),
        };

        final body = switch (_section) {
          _Section.play => PlayerPlayPage(
            ctrl: _ctrl,
            hydrating: _hydrating,
            currentGameClosed: _isCurrentGameClosed(),
            onDigitsChanged: _onDigitsChanged,
            onPlay: _play,
            onReserve: _reserve,
            onRetry: () => _ctrl.retry(),
            onOpenPlans: () => setState(() => _section = _Section.plan),
            onOpenReferrals: () =>
                setState(() => _section = _Section.referrals),
          ),
          _Section.history => PlayerHistoryPage(
            items: _ctrl.history,
            onRefresh: () => _ctrl.loadHistory(),
            locked: !historyUnlocked,
            onOpenPlans: () => setState(() => _section = _Section.plan),
          ),
          _Section.referrals => PlayerReferralsPage(
            code: _ctrl.referralCode,
            onOpenPlans: () => setState(() => _section = _Section.plan),
          ),
          _Section.plan => const PlayerPlanPage(),
          _Section.help => const PlayerHelpPage(),
        };

        final shell = WebShellLayout(
          items: [
            const WebNavItem(Icons.casino_outlined, 'Jugar'),
            const WebNavItem(Icons.history_rounded, 'Historial'),
            const WebNavItem(Icons.groups_2_outlined, 'Referidos'),
            const WebNavItem(Icons.workspace_premium_outlined, 'Mi plan'),
            const WebNavItem(Icons.help_outline_rounded, 'Ayuda'),
          ],
          selected: _section.index,
          onSelect: (i) {
            setState(() => _section = _Section.values[i]);
            if (_section == _Section.history) _ctrl.loadHistory();
            if (_section == _Section.referrals) {
              context.read<ReferralProvider>().load();
            }
          },
          title: title,
          subtitle: subtitle,
          userName: _userName,
          userRole: subs.isPremium
              ? (subs.isTrial ? 'Prueba gratuita' : 'Jugador PRO')
              : 'Jugador',
          onLogout: _logout,
          actions: [
            if (!subs.isPremium && !WebBreakpoints.isMobile(context))
              _ProChip(onTap: () => setState(() => _section = _Section.plan)),
            WebIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notificaciones',
              badge: unread,
              onPressed: _openNotifications,
            ),
            WebIconButton(
              icon: Icons.manage_accounts_outlined,
              tooltip: 'Mi cuenta y privacidad',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountPrivacyScreen()),
              ),
            ),
          ],
          body: body,
        );

        // La balota que se está reservando flota sobre toda la pantalla.
        final big = _ctrl.currentBigBall;
        return Stack(
          children: [
            Positioned.fill(child: shell),
            Positioned.fill(
              child: BallRevealOverlay(
                active: _ctrl.reserving,
                number: big == null
                    ? null
                    : formatGameNumber(big, _ctrl.digitsPerBall),
                index: _ctrl.displayedBalls.length + (big == null ? 0 : 1),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ProChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: WebPalette.goldGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                size: 18,
                color: Color(0xFF1A1300),
              ),
              const SizedBox(width: 8),
              Text(
                'Hazte PRO',
                style: WebPalette.body(
                  13.5,
                  weight: FontWeight.w800,
                  color: const Color(0xFF1A1300),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _NotificationsList({required this.items});

  String _fmt(String raw) {
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return raw;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_off_outlined,
        title: 'Sin notificaciones',
        message: 'Aquí verás la programación de sorteos, resultados y pagos.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final n = items[i];
        final kind = (n['kind'] ?? '').toString();
        final (icon, color) = switch (kind) {
          'you_won' => (Icons.emoji_events_rounded, WebPalette.emerald),
          'schedule_set' => (
            Icons.event_available_rounded,
            WebPalette.goldLight,
          ),
          _ when kind.contains('payout') || kind.contains('pago') => (
            Icons.payments_outlined,
            WebPalette.emerald,
          ),
          _ when kind.contains('reject') => (
            Icons.cancel_outlined,
            WebPalette.danger,
          ),
          _ => (Icons.notifications_rounded, WebPalette.gold),
        };
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(
              alpha: n['read'] == true ? 0.025 : 0.06,
            ),
            border: Border.all(color: WebPalette.glassBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: color.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (n['title'] ?? 'Notificación').toString(),
                      style: WebPalette.body(
                        14,
                        weight: FontWeight.w700,
                        color: WebPalette.text,
                      ),
                    ),
                    if ((n['body'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(n['body'].toString(), style: WebPalette.body(13)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _fmt((n['created_at'] ?? '').toString()),
                      style: WebPalette.body(11.5, color: WebPalette.textFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
