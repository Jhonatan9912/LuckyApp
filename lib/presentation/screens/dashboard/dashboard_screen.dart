import 'package:flutter/material.dart';
import 'widgets/ball_tube.dart';
import 'widgets/play_button.dart';
import 'widgets/action_buttons.dart';
import 'controller/dashboard_controller.dart';
import 'widgets/help_bottom_sheet.dart';
import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/data/api/games_api.dart';
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/domain/auth/auth_repository.dart';
import 'widgets/empty_selection_placeholder.dart';
import 'package:base_app/core/config/env.dart';
import 'package:base_app/core/utils/formatters.dart';
import 'widgets/dashboard_app_bar.dart';
import 'widgets/selection_row.dart';
import 'widgets/big_ball_overlay.dart';
import 'dart:async';
import 'widgets/selection_tabs.dart' as tabs;
import 'widgets/history_panel.dart' as hist;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart'; // (si aún no lo tienes)
import 'package:base_app/presentation/providers/subscription_provider.dart';
import 'package:base_app/presentation/widgets/premium_gate.dart';
import 'package:base_app/presentation/widgets/subscription/subscription_sheet.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:base_app/presentation/widgets/referrals/referral_payout_tile.dart';
import 'package:base_app/presentation/screens/referrals/referrals_tab.dart';
import 'package:base_app/presentation/widgets/payout_request_sheet.dart';
import 'package:base_app/presentation/widgets/notifications/notifications_bottom_sheet.dart';
import 'package:base_app/core/utils/url_utils.dart';
import 'package:base_app/core/config/links.dart';
import 'widgets/social_dock.dart';
import 'widgets/social_dock_with_label.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';
import 'package:base_app/presentation/screens/dashboard/logic/game_mode.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _hydrating = true; // ← mientras hidrato estado inicial, oculto JUGAR/placeholder
  bool _dialogBusy = false; // evita abrir 2 diálogos a la vez
  bool _scheduleShownOnce = false; // no repetir alerta de programado

  VoidCallback? _subsListener;

  Future<void> _safeShow(Future<void> Function() task) async {
    if (!mounted || _dialogBusy) return;
    _dialogBusy = true;
    try {
      await task();
    } finally {
      _dialogBusy = false;
    }
  }

  late final DashboardController _ctrl;

  Timer? _notifTimer; // 👈 timer para notificaciones
  int _tabIndex = 0; // 0 = Juego, 1 = Historial
  // Espaciados (ajústalos a tu gusto)


double gapTop = 0;        // 0 o 4
double gapTubeTabs = 0;   // ya no lo usas, puedes dejarlo en 0 o borrarlo
double gapGameTop = 8;    // 8 o 10
double gapHistoryTop = 8;

  // === espacio inferior dinámico para que nada quede debajo del FAB/JUGAR ===
  double get _contentBottomSafe {
    
    const double buttonsHeight = 72; // alto aprox del botón + sombra
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return bottomInset + buttonsHeight + 16; // margen extra
  }
int get uiDigits => _ctrl.digitsPerBall;

Future<void> _showReserveSuccessDialog({required bool completed}) async {
  if (!mounted) return;

  final rawNumbers = _ctrl.numbers;

  // ---------- Cálculo ROBUSTO de dígitos ----------
  int digits = uiDigits; // fuente de verdad (controller)

  if (digits <= 0) digits = 3;

  // Si algún número tiene más cifras, nos ajustamos a eso
  int inferred = digits;
  for (final n in rawNumbers) {
    final len = n.toString().length;
    if (len > inferred) inferred = len;
  }

  // Normalizamos un poco (mínimo 3, máximo 6 por seguridad)
  if (inferred < 3) inferred = 3;
  if (inferred > 6) inferred = 6;
  digits = inferred;

final formatted = rawNumbers
    .map((n) => formatGameNumber(n, uiDigits))
    .join(' - ');

  final title = '¡Reserva confirmada!';
  final message = completed
      ? 'Tus números se han reservado:\n$formatted\n\nEl juego se completó y se abrió uno nuevo automáticamente.'
      : 'Tus números se han reservado:\n$formatted';

  await _showSuccess(message, title: title);

  if (completed && mounted) {
    _ctrl.resetToInitial();
    setState(() {});
  }
}

void _onDigitsChanged(int value) async {
  if (uiDigits == value) return;

  // 2 cifras siempre está permitido (gratis)
  if (value != 2) {
    final subs = context.read<SubscriptionProvider>();
    final int maxDigits = subs.maxDigits ?? 3;

    if (value > maxDigits) {
      await _openSubscriptionSheet();
      return;
    }
  }

  _ctrl.setDigitsPerBall(value);

  setState(() => _hydrating = true);
  await _ctrl.loadHistory();
  await _ctrl.restoreSelectionIfAny();
  if (mounted) setState(() => _hydrating = false);
}

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const HelpBottomSheet(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = SessionManager();
    final gamesApi = GamesApi(baseUrl: Env.apiBaseUrl);
    final authApi = AuthApi(baseUrl: Env.apiBaseUrl);
    final authRepo = AuthRepository(api: authApi, session: session);

    _ctrl = DashboardController(
      gamesApi: gamesApi,
      authRepo: authRepo,
      session: session,
      devUserId: 8,
    );

    // Sincroniza PRO con el provider (lo de siempre)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final subs = context.read<SubscriptionProvider>();

_subsListener = () {
  _ctrl.applyPremiumFromStore(
    premium: subs.isPremium,
    planDigits: subs.maxDigits ?? 3,
  );
};
subs.addListener(_subsListener!);

_ctrl.applyPremiumFromStore(
  premium: subs.isPremium,
  planDigits: subs.maxDigits ?? 3,
);

    });

    // 🔹 HIDRATACIÓN INICIAL
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ctrl.initSession();
      if (!mounted) return;

      if (!_ctrl.sessionReady) {
        // Sin sesión: igual dejamos mostrar el botón JUGAR
        if (mounted) setState(() => _hydrating = false);
        return;
      }

      setState(() => _hydrating = true);
      await _ctrl.loadHistory();
      _ctrl.resetToInitial();
      if (mounted) setState(() => _hydrating = false);

      // ====== resto de tu código tal cual ======
      final subs = context.read<SubscriptionProvider>();
      final refs = context.read<ReferralProvider>();
      unawaited(subs.configureBilling());
      unawaited(subs.refresh(force: true));
      unawaited(refs.load(refresh: true));
      unawaited(_ctrl.loadReferralCode());

      await _safeShow(() async {
        await _checkScheduleNotice();
      });

      await _ctrl.loadNotifications();
      await _safeShow(() async {
        await _checkNotifications();
      });

      _notifTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_dialogBusy) return;

        await _ctrl.loadNotifications();
        await _safeShow(() async {
          await _checkNotifications();
        });

        if (!_scheduleShownOnce) {
          await _safeShow(() async {
            await _checkScheduleNotice();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _notifTimer?.cancel(); // 👈 cancela el timer al cerrar la pantalla
    _ctrl.dispose();

    // 🔻 Quita el listener para evitar leaks
    try {
      final subs = context.read<SubscriptionProvider>();
      if (_subsListener != null) subs.removeListener(_subsListener!);
    } catch (_) {
      // Si el provider ya no está en el árbol, ignoramos
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
return AnimatedBuilder(
  animation: _ctrl,
  builder: (context, __) {
      final subs = context.watch<SubscriptionProvider>();
      final isPro = subs.isPremium;

      // 👇 Nuevo: cuántas cifras tiene permitido el usuario según su plan
      final int maxDigits = subs.maxDigits ?? 3; // 20k => 3, 60k => 4

      return Scaffold(
        appBar: DashboardAppBar(
          onHelp: _showHelp,
          isLoggedIn: _ctrl.authToken?.isNotEmpty == true,
          onLogout: () async {
            if (!mounted) return;
            if (_dialogBusy) return;
            _dialogBusy = true;

            final navigator = Navigator.of(context, rootNavigator: true);
            final messenger = ScaffoldMessenger.maybeOf(context);
            final subs = context.read<SubscriptionProvider>();

            try {
              _notifTimer?.cancel();
              _notifTimer = null;

              showDialog(
                context: navigator.context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              subs.clear();
              await _ctrl.logout();

              while (navigator.canPop()) {
                navigator.pop();
              }
              navigator.pushNamedAndRemoveUntil('/login', (_) => false);
            } catch (e) {
              if (navigator.canPop()) navigator.pop();
              messenger?.showSnackBar(
                SnackBar(content: Text('No se pudo cerrar sesión: $e')),
              );
            } finally {
              _dialogBusy = false;
            }
          },
          ctrl: _ctrl,
          onBellTap: _openNotifications,
        ),

        floatingActionButton: isPro
            ? null
            : FloatingActionButton.extended(
                onPressed: () => Navigator.pushNamed(context, '/pro'),
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Pro'),
              ),

        body: SafeArea(
          top: false,
          bottom: true,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFF9F0), Color(0xFFFFF3D8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: gapTop),

                    Consumer<ReferralProvider>(
                      builder: (_, p, __) => ReferralPayoutTile(
                        code: _ctrl.referralCode,
                        minToWithdraw: 100000,
                        onWithdraw: () async {
                          final submitted = await showPayoutRequestSheet(context);

                          if (submitted == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Solicitud de retiro enviada')),
                            );
                          }
                        },
                      ),
                    ),

if (isPro) ...[
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
    child: _ProBadge(onTap: _openSubscriptionSheet),
  ),
  const SizedBox(height: 10), // ✅ separación PRO ↔ Tipo de juego
],


// ❌ QUITA este wrapper:
// Transform.translate(offset: const Offset(0, -20), child: Column(...))

Column(
  children: [
    if (_tabIndex == 0)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Center(
          child: _GameModeSelector(
            digits: uiDigits,
            maxDigits: maxDigits,
            disabled: _ctrl.animating || _ctrl.reserving,
            onChanged: _onDigitsChanged,
          ),
        ),
      ),

    // ❌ QUITA ESTO para no meter más espacio:
    // const SizedBox(height: 4),

    // ✅ Si aún ves espacio, ajusta -8 / -10 / -12
Transform.translate(
  offset: const Offset(0, -10),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      BallTube(
        numbers: _ctrl.numbers,
        animating: _ctrl.animating,
        digits: uiDigits,
      ),
    ],
  ),
),


    // ✅ Tabs pueden seguir subiendo, eso está bien
    Transform.translate(
      offset: const Offset(0, -60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: tabs.SelectionTabs(
          index: _tabIndex,
          historyUnlocked: _ctrl.mode.isFreeMode ||
              (isPro && (subs.maxDigits ?? 0) >= uiDigits),
          onHistoryLocked: _openSubscriptionSheet,
          onChanged: (i) async {
            setState(() => _tabIndex = i);
            if (i == 1) {
              await _ctrl.loadHistory();
            } else if (i == 0) {
              await _ctrl.loadHistory();
              setState(() {});
            } else if (i == 2) {
              await context.read<ReferralProvider>().load();
            }
          },
        ),
      ),
    ),
  ],
),


                    if (_tabIndex == 0) ...[
                      SizedBox(height: gapGameTop),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, _contentBottomSafe),
                              child: PremiumGate(
                                bypass: _ctrl.mode.isFreeMode,
                                onGoPro: () => Navigator.pushNamed(context, '/pro'),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: _hydrating
                                      ? const SizedBox.shrink()
                                      : (_ctrl.hasAdded && !_isCurrentGameClosed())
                                          ? Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: SelectionRow(
                                                balls: _ctrl.displayedBalls,
                                                digits: uiDigits,
                                              ),
                                            )
                                          : EmptySelectionPlaceholder(digits: uiDigits),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ] else if (_tabIndex == 1) ...[
                      SizedBox(height: gapHistoryTop),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, _contentBottomSafe),
                          child: hist.HistoryPanel(
                            items: _ctrl.history,
                            onRefresh: () => _ctrl.loadHistory(),
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(height: gapHistoryTop),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(0, 0, 0, _contentBottomSafe),
                          child: const ReferralsTab(),
                        ),
                      ),
                    ],
                  ],
                ),

                BigBallOverlay(
                  number: _ctrl.currentBigBall,
                  digits: uiDigits,
                ),

                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        final offsetAnimation = Tween<Offset>(
                          begin: const Offset(0.0, 0.3),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                        );
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: offsetAnimation,
                            child: child,
                          ),
                        );
                      },
                      child: _buildBottomButtons(),
                    ),
                  ),
                ),

                if (_tabIndex == 0)
                  Positioned(
                    right: 16,
                    bottom: _contentBottomSafe,
                    child: const SocialDockWithLabel(),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}


                   
  Widget _buildBottomButtons() {
    // si NO está en Juego Actual, no mostramos botones de juego
    if (_tabIndex != 0) {
      return const SizedBox.shrink();
    }
  if (_hydrating) return const SizedBox.shrink();
    // Lee el provider UNA vez aquí
    final subs = context.watch<SubscriptionProvider>();
    final isPremium = subs.isPremium;
    final isFreeMode = _ctrl.mode.isFreeMode; // 2 cifras = gratis

    // Mientras carga suscripción, mostrar JUGAR si aún no ha jugado
    // (generateLocalPreview es 100% local, no necesita backend)
    if (subs.loading || subs.activating) {
      if (!_ctrl.hasPlayedOnce) {
        return PlayButton(
          onPressed: () async {
            if (!_ctrl.animating && !_ctrl.saving) {
              await _ctrl.generateLocalPreview();
            }
          },
          key: const ValueKey('play_loading'),
        );
      }
      return const SizedBox.shrink();
    }

    // 1) FREE y NO en modo gratis: botón JUGAR local (sin backend)
    if (!isPremium && !isFreeMode) {
      return PlayButton(
        onPressed: () async {
          if (!_ctrl.animating && !_ctrl.saving) {
            await _ctrl.generateLocalPreview();
          }
        },
        key: const ValueKey('play_free'),
      );
    }

    // 2) PRO o modo gratis (2 cifras): lógica completa
    if (_ctrl.showFinalButtons) {
      // Oculta mientras se está reservando (animación + commit)
      if (_ctrl.reserving) return const SizedBox.shrink();

      // Reserva completada: no mostramos botones
      if (_ctrl.hasAddedFinal) return const SizedBox.shrink();

      return ActionButtons(
        onAdd: () async {
          final out = await _ctrl.add();
          if (!mounted) return;

          if (out.ok) {
            if (out.code == 'REPLACED' && out.message != null) {
              await _showInfo(out.message!);
            } else {
              await _showReserveSuccessDialog(completed: out.gameCompleted);
            }
          } else {
            final code = out.code ?? '';
            final msg = out.message ?? 'No se pudo guardar la selección.';

            if (code == 'CONFLICT' || code == 'GAME_SWITCHED') {
              await _showWarn(msg);
              if (!mounted) return;
              _ctrl.resetToInitial();
              setState(() {});
              await _ctrl.openFreshGame();
              return;
            } else if (code == 'UNAUTHORIZED' || code == 'UNAUTHENTICATED' || code == 'TOKEN_EXPIRED') {
              if (isFreeMode) {
                await _showWarn('Tu sesión expiró. Inicia sesión de nuevo para reservar.');
              } else {
                final nav = Navigator.of(context, rootNavigator: true);
                await _showError(msg);
                if (!mounted) return;
                nav.pushNamedAndRemoveUntil('/login', (_) => false);
              }
            } else {
              await _showError(msg);
            }
          }
        },
        onRetry: () async => _ctrl.retry(),
        isSaving: _ctrl.saving,
        isPremium: isPremium || isFreeMode,
        onGoPro: () => Navigator.pushNamed(context, '/pro'),
      );
    }


// Estado inicial: solo "JUGAR" (para PRO)
if (!_ctrl.hasPlayedOnce) {
  return PlayButton(
    onPressed: () async {
      if (!_ctrl.animating && !_ctrl.saving) {
        // ✅ Solo preview local, SIN tocar backend
        await _ctrl.generateLocalPreview();
      }
    },
    key: const ValueKey('play_pro'),
  );
}


    return const SizedBox.shrink();
  }

  Future<void> _showError(String msg) async {
    if (!mounted) {
      return;
    }
    await AppDialogs.error(context: context, title: 'Error', message: msg);
  }

  Future<void> _showSuccess(String msg, {String title = '¡Listo!'}) async {
    if (!mounted) return;
    await AppDialogs.success(
      context: context,
      title: title,
      message: msg,
      okText: 'OK',
    );
  }

  // ignore: unused_element
  Future<void> _showInfo(String msg) async {
    if (!mounted) return;
    await AppDialogs.success(
      context: context,
      title: 'Información',
      message: msg,
      okText: 'OK',
    );
  }

  Future<void> _showWarn(String msg) async {
    if (!mounted) return;
    await AppDialogs.warning(context: context, title: 'Aviso', message: msg);
  }

Future<void> _checkNotifications() async {
  final notifs = await _ctrl.fetchWinnerNotificationsOnce();
  if (!mounted || notifs.isEmpty) return;

  final shownIds = <int>[];

  for (final n in notifs) {
    if (!mounted) return;

    final id = n['id'] as int?;
    final gameId = n['game_id'];

    final rawWinning = (n['winning_number'] ?? '').toString();

    // ================= CÁLCULO ROBUSTO DE DÍGITOS =================
    // Primero intentar leer del payload de la notificación
    final notifDigits = n['digits'] as int?;
    int digits = notifDigits ?? 3;

    if (notifDigits == null) {
      // 1) Intentar usar la info del historial de ese mismo juego
      Map<String, dynamic>? histItem;
      for (final h in _ctrl.history) {
        final gidNum = (h['game_id'] ?? h['id']) as num?;
        if (gidNum != null && gidNum.toInt() == gameId) {
          histItem = h as Map<String, dynamic>;
          break;
        }
      }

      if (histItem != null) {
        final histWin = histItem['winning_number'];
        final rawNums = (histItem['numbers'] as List?) ?? const [];

        int inferred = 2;

        if (histWin != null) {
          final len = histWin.toString().length;
          if (len > inferred) inferred = len;
        }

        for (final x in rawNums) {
          final len = x.toString().length;
          if (len > inferred) inferred = len;
        }

        if (inferred < 2) inferred = 2;
        if (inferred > 6) inferred = 6;

        digits = inferred;
      } else {
        final len = rawWinning.replaceAll('-', '').length;
        if (len >= 5) {
          digits = 5;
        } else if (len == 4) {
          digits = 4;
        } else if (len <= 2) {
          digits = 2;
        } else {
          digits = 3;
        }
      }
    }

    final wn = int.tryParse(rawWinning) ?? 0;

String numStr;
if (digits == 5) {
  final s = wn.toString().padLeft(5, '0');   // 00000..99999
  numStr = '${s.substring(0, 4)}-${s.substring(4)}'; // 1234-5
} else {
  numStr = wn.toString().padLeft(digits, '0'); // 000 / 0000
}

    // =============================================================

    final kind = (n['kind'] ?? '').toString();

    if (kind == 'you_won') {
      await AppDialogs.success(
        context: context,
        title: '🏆 ¡Fuiste el ganador del juego #$gameId!',
        message: 'Ganaste con el número $numStr',
        okText: '¡Genial!',
      );
    } else {
      await AppDialogs.success(
        context: context,
        title: '🎉 ¡Resultado del juego #$gameId!',
        message: 'El número ganador es $numStr',
        okText: 'OK',
      );
    }

    // 👇 Al anunciarse el ganador, dejamos el "Juego actual" en estado inicial
    if (mounted) {
      _ctrl.resetToInitial(); // limpia flags y deja visible el botón "JUGAR"
      setState(() {});        // fuerza el rebuild de la pantalla
    }

    if (id != null) shownIds.add(id);
  }

  // (Opcional) marcar como leídas en backend:
  // await _gamesApi.markNotificationsRead(ids: shownIds, token: _ctrl.authToken);
}


  Future<void> _checkScheduleNotice() async {
    // 1) Intenta desde listado (notifs normales)
    var item = await _ctrl.fetchScheduleFromListOnce();

    // 2) Si no hay, intenta el peek (programación “silenciosa”)
    item ??= await _ctrl.peekScheduleOnce();

    if (!mounted || item == null) return;

    // Construimos una clave única de esta programación.
    // Preferimos ID; si no viene, usamos game_id + fecha/hora + título/cuerpo.
    final scheduleKey = [
      (item['id'] ?? '').toString(),
      (item['game_id'] ?? '').toString(),
      (item['scheduled_at'] ?? item['when'] ?? '').toString(),
      (item['title'] ?? '').toString(),
      (item['body'] ?? '').toString(),
    ].join('|');

    // Si ya se mostró esta programación, no la muestres de nuevo.
    final lastKey = await _getLastScheduleKey();
    if (lastKey == scheduleKey) {
      _scheduleShownOnce = true; // evita reintentos en este ciclo
      // (opcional) si vino con id, márcala leída en backend
      final nid = int.tryParse((item['id'] ?? '').toString());
      if (nid != null) {
        await _ctrl.markReadIds([nid]);
      }
      return;
    }

    // Mostrar alerta
    final title = (item['title'] ?? '¡Juego programado!').toString();
    final body = (item['body'] ?? '').toString();
    if (!mounted) return;
    await AppDialogs.success(
      context: context,
      title: title,
      message: body,
      okText: 'OK',
    );

    // Marcar como mostrada (en memoria y persistente)
    _scheduleShownOnce = true;
    await _setLastScheduleKey(scheduleKey);

    // Si la notificación tiene id, márcala como leída
    final nid = int.tryParse((item['id'] ?? '').toString());
    if (nid != null) {
      await _ctrl.markReadIds([nid]);
    }
  }

  Future<void> _openSubscriptionSheet() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SubscriptionSheet(), // 👈 AQUÍ EL CAMBIO
    );
  }

  Future<void> _openNotifications() async {
    if (!mounted) return;

    _dialogBusy = true;
    try {
      // 1) Carga
      await _ctrl.loadNotifications();

      // 2) Marca TODAS las no leídas como leídas
      await _ctrl.markUnreadAsRead();

      // 👇 chequeo extra ANTES de usar context
      if (!mounted) return;

      // 3) Muestra tu UI de notificaciones (sheet o pantalla)
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          final items = _ctrl.notifications;
          return NotificationsBottomSheet(items: items);
        },
      );
    } finally {
      _dialogBusy = false;
    }
  }

  bool _isCurrentGameClosed() {
    final gid = _ctrl.gameId;
    if (gid == null) return false;

    for (final m in _ctrl.history) {
      final mid = (m['game_id'] as num?)?.toInt();
      if (mid != gid) continue;

      final status = (m['status'] ?? m['result'] ?? '')
          .toString()
          .toLowerCase();
      final hasWinner =
          m['winning_number'] != null ||
          status.contains('closed') ||
          status.contains('completed') ||
          status.contains('perdido') ||
          status.contains('ganado');

      return hasWinner;
    }
    return false;
  }

  Future<String?> _getLastScheduleKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_schedule_key');
  }

  Future<void> _setLastScheduleKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_schedule_key', key);
  }
}

class _ProBadge extends StatelessWidget {
  final VoidCallback? onTap;
  const _ProBadge({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD4AF37), Color(0xFFA07800)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55D4AF37),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.workspace_premium, size: 18, color: Color(0xFF0A0A0A)),
            SizedBox(width: 6),
            Text(
              'PRO ACTIVO',
              style: TextStyle(
                color: Color(0xFF0A0A0A),
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameModeSelector extends StatelessWidget {
  final int digits;
  final int maxDigits;
  final bool disabled;
  final ValueChanged<int> onChanged;

  const _GameModeSelector({
    required this.digits,
    required this.maxDigits,
    required this.disabled,
    required this.onChanged,
  });

  String _label(int d) => switch (d) {
    2 => '2 Cifras',
    3 => '3 Cifras',
    4 => '4 Cifras',
    5 => 'Quinta',
    _ => '$d Cifras',
  };

  @override
  Widget build(BuildContext context) {
    final entries = [2, 3, if (maxDigits >= 4) 4, if (maxDigits >= 5) 5];

    return PopupMenuButton<int>(
      enabled: !disabled,
      onSelected: onChanged,
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF4A4228)),
      ),
      color: Colors.white,
      itemBuilder: (_) => entries
          .map(
            (d) => PopupMenuItem<int>(
              value: d,
              child: Row(
                children: [
                  if (d == digits)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check, size: 16, color: Color(0xFFD4AF37)),
                    )
                  else
                    const SizedBox(width: 24),
                  Text(
                    _label(d),
                    style: TextStyle(
                      color: d == digits
                          ? const Color(0xFFB8860B)
                          : const Color(0xFF1A1A1A),
                      fontWeight: d == digits ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22D4AF37),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.casino_outlined, size: 15, color: Color(0xFFB8860B)),
              const SizedBox(width: 6),
              Text(
                _label(digits),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF6B4E00),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: Color(0xFFB8860B)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialHintBubble extends StatelessWidget {
  final String text;
  final VoidCallback? onClose;
  const _SocialHintBubble({required this.text, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surface.withValues(alpha: 0.98);
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.35);

    return Material(
      color: bg,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12.5, height: 1.25),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onClose,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
