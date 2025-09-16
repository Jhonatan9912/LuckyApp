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
  double gapTop = 1; // espacio desde arriba hasta el tubo
  double gapTubeTabs = 40; // espacio entre el tubo y las pestañas

  double gapGameTop = 32; // menos margen arriba
  double gapHistoryTop = 8;

  // === espacio inferior dinámico para que nada quede debajo del FAB/JUGAR ===
  double get _contentBottomSafe {
    const double buttonsHeight = 72; // alto aprox del botón + sombra
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return bottomInset + buttonsHeight + 16; // margen extra
  }

  Future<void> _showReserveSuccessDialog({required bool completed}) async {
    if (!mounted) return;
    final formatted = _ctrl.numbers.toTriplePadded();
    final title = '¡Reserva confirmada!';
    final message = completed
        ? 'Tus números se han reservado:\n$formatted\n\nEl juego se completó y se abrió uno nuevo automáticamente.'
        : 'Tus números se han reservado:\n$formatted';

    await _showSuccess(message, title: title);

    // 👇 Si el juego se cerró, deja la pestaña en estado inicial (botón JUGAR)
    if (completed && mounted) {
      _ctrl.resetToInitial();
      setState(() {});
    }
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
    // 🔗 Sincroniza el flag PRO del controller con el provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final subs = context.read<SubscriptionProvider>();

      // Listener que copia subs.isPremium → controller
      _subsListener = () {
        _ctrl.applyPremiumFromStore(subs.isPremium);
      };
      subs.addListener(_subsListener!);

      // Sincronización inicial (por si ya venías PRO)
      _ctrl.applyPremiumFromStore(subs.isPremium);
    });

    // ... dentro de initState(), en el segundo addPostFrameCallback:
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _ctrl.initSession();
    if (!mounted || !_ctrl.sessionReady) return;

    // ★ INICIO hidratación: oculta JUGAR y el placeholder
    setState(() => _hydrating = true);

    // Primero historia y restaurar selección (para pintar balotas si existen)
    await _ctrl.loadHistory();            // necesario para descartar juegos cerrados
    await _ctrl.restoreSelectionIfAny();  // pinta números y pone hasAddedFinal=true

    // ★ FIN hidratación: ya puedo decidir si muestro balotas o JUGAR
    if (mounted) setState(() => _hydrating = false);

    // (de aquí en adelante deja lo demás como ya lo tienes: billing, refs, notifs, timers…)
    final subs = context.read<SubscriptionProvider>();
    final refs = context.read<ReferralProvider>();
    unawaited(subs.configureBilling());
    unawaited(subs.refresh(force: true));
    unawaited(refs.load(refresh: true));
    unawaited(_ctrl.loadReferralCode());


      // 1) Peek de juego programado (solo una vez)
      await _safeShow(() async {
        await _checkScheduleNotice();
      });

      // 2) Notificaciones normales (ganador, etc.)
      await _ctrl.loadNotifications();
      await _safeShow(() async {
        await _checkNotifications();
      });

      // 3) Polling cada 5s (evita correr si hay diálogo abierto)
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

        return Scaffold(
          appBar: DashboardAppBar(
            onHelp: _showHelp,
            isLoggedIn: _ctrl.authToken?.isNotEmpty == true,
            onLogout: () async {
              if (!mounted) return;
              if (_dialogBusy) return;
              _dialogBusy = true;

              // Captura todo lo que depende de context ANTES de await:
              final navigator = Navigator.of(context, rootNavigator: true);
              final messenger = ScaffoldMessenger.maybeOf(context);
              final subs = context.read<SubscriptionProvider>();

              try {
                // Cancela timers
                _notifTimer?.cancel();
                _notifTimer = null;

                // Loading (usa navigator ya capturado)
                showDialog(
                  context: navigator.context, // <- evita reconsultar context
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );

                // Limpia estado/app
                subs.clear();
                await _ctrl.logout(); // ya borra sesión local

                // Cierra overlays y navega (sin volver a usar context)
                while (navigator.canPop()) {
                  navigator.pop();
                }
                navigator.pushNamedAndRemoveUntil('/login', (_) => false);
              } catch (e) {
                // Cierra loading si quedó abierto
                if (navigator.canPop()) navigator.pop();
                messenger?.showSnackBar(
                  SnackBar(content: Text('No se pudo cerrar sesión: $e')),
                );
              } finally {
                _dialogBusy = false;
              }
            },

            ctrl: _ctrl, // 👈 pasa el controlador
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
                  colors: [Color(0xFFFFF7E6), Color(0xFFFFE7BA)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                children: [
                  // ======= COLUMNA PRINCIPAL: tubo + tabs + contenido =======
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: gapTop), // <-- usa variable
                      // 👇 Banner de referido (nuevo)
                      Consumer<ReferralProvider>(
                        builder: (_, p, __) => ReferralPayoutTile(
                          code: _ctrl.referralCode,
                          minToWithdraw: 100000, // umbral de $100.000 COP
                          onWithdraw: () async {
                            final submitted = await showPayoutRequestSheet(
                              context,
                            );

                            if (submitted == true && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Solicitud de retiro enviada'),
                                ),
                              );
                            }
                          },
                        ),
                      ),

                      if (isPro)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: _ProBadge(onTap: _openSubscriptionSheet),
                        ),

                      Column(
                        children: [
                          BallTube(
                            numbers: _ctrl.numbers,
                            animating: _ctrl.animating,
                          ),
                          const SizedBox(
                            height: 8,
                          ), // 👈 AQUÍ controlas el espacio real
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: tabs.SelectionTabs(
                              index: _tabIndex,
                              onChanged: (i) async {
                                setState(() => _tabIndex = i);

                                if (i == 1) {
                                  // Historial
                                  await _ctrl.loadHistory();
                                } else if (i == 0) {
                                  // Juego Actual
                                  await _ctrl
                                      .loadHistory(); // por si hubo ganador
                                  setState(() {});
                                } else if (i == 2) {
                                  // Mis referidos
                                  await context.read<ReferralProvider>().load();
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      if (_tabIndex == 0) ...[
                        // ===== Juego Actual =====
                        SizedBox(height: gapGameTop),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  _contentBottomSafe,
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: PremiumGate(
                                    onGoPro: () =>
                                        Navigator.pushNamed(context, '/pro'),
                                        child: Center(
                                          child: _hydrating
                                              ? const SizedBox.shrink() // ★ nada mientras hidratas
                                              : (_ctrl.hasAdded && !_isCurrentGameClosed())
                                                  ? Padding(
                                                      padding: const EdgeInsets.only(top: 6),
                                                      child: SelectionRow(
                                                        balls: _ctrl.displayedBalls,
                                                        showActions: _ctrl.showActionIcons,
                                                        onClear: _ctrl.clearSelection,
                                                      ),
                                                    )
                                                  : const EmptySelectionPlaceholder(),
                                        ),

                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ] else if (_tabIndex == 1) ...[
                        // ===== Historial =====
                        SizedBox(height: gapHistoryTop),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              _contentBottomSafe,
                            ),

                            child: hist.HistoryPanel(
                              items: _ctrl.history,
                              onRefresh: () => _ctrl.loadHistory(),
                            ),
                          ),
                        ),
                      ] else ...[
                        // ===== Mis referidos =====
                        SizedBox(height: gapHistoryTop),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              0,
                              0,
                              0,
                              _contentBottomSafe,
                            ),
                            child: const ReferralsTab(),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // ======= OVERLAY: Balota grande =======
                  BigBallOverlay(number: _ctrl.currentBigBall),

                  // ======= OVERLAY: Botones inferiores =======
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          final offsetAnimation =
                              Tween<Offset>(
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

                // ======= OVERLAY: Dock social con etiqueta (solo en "Juego Actual") =======
                if (_tabIndex == 0)
                  Positioned(
                    right: 16,
                    bottom: _contentBottomSafe, // justo encima del botón JUGAR/FAB
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

    // Mientras se verifica PRO/Free o se está activando tras una compra,
    // no mostramos nada para evitar parpadeo.
    if (subs.loading || subs.activating) {
      return const SizedBox.shrink();
    }

    final isPremium = subs.isPremium;

    // 1) FREE: botón JUGAR local (sin backend)
    if (!isPremium) {
      return PlayButton(
        onPressed: () async {
          if (!_ctrl.animating && !_ctrl.saving) {
            await _ctrl.generateLocalPreview(); // local ✅
          }
        },
        key: const ValueKey('play_free'),
      );
    }

    // 2) PRO: lógica normal
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
            } else if (code == 'UNAUTHORIZED' || code == 'UNAUTHENTICATED') {
              final nav = Navigator.of(context, rootNavigator: true);
              await _showError(msg);
              if (!mounted) return;
              nav.pushNamedAndRemoveUntil('/login', (_) => false);
            } else {
              await _showError(msg);
            }
          }
        },
        onRetry: () async => _ctrl.retry(),
        isSaving: _ctrl.saving,
        isPremium: isPremium, // ← usa la variable local
        onGoPro: () => Navigator.pushNamed(context, '/pro'),
      );
    }

    // Estado inicial: solo "JUGAR" (para PRO)
    if (!_ctrl.hasPlayedOnce) {
      return PlayButton(
        onPressed: () async {
          if (!_ctrl.animating && !_ctrl.saving) {
            await _ctrl.openFreshGame();
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
      final numStr = (n['winning_number'] ?? '').toString().padLeft(3, '0');
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
      // Después de AppDialogs.success(...) para ganador o resultado:
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Únete a nuestro canal para enterarte de los próximos sorteos 🎁'),
            action: SnackBarAction(
              label: 'Ir ahora',
              onPressed: () => UrlUtils.openExternal(
                context,
                url: AppLinks.whatsappChannel,
              ),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // 👇 Al anunciarse el ganador, dejamos el "Juego actual" en estado inicial
      if (mounted) {
        _ctrl.resetToInitial(); // limpia flags y deja visible el botón "JUGAR"
        setState(() {}); // fuerza el rebuild de la pantalla
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
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFD700), // dorado
              Color(0xFFB57EDC), // púrpura suave
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.workspace_premium, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'PRO activo',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
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
