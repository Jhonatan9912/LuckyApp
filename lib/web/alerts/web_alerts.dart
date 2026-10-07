// lib/web/alerts/web_alerts.dart
//
// Sistema de alertas de la versión web:
//  • Toasts (éxito / aviso / info): esquina superior derecha, no bloquean,
//    se cierran solos con barra de progreso (se pausa al pasar el mouse).
//  • Modales (error / confirmación): fondo desenfocado, animación de entrada,
//    Enter = aceptar, Esc = cancelar.
//
// Se pintan sobre toda la ventana (por encima del Navigator), así se ven
// igual en las pantallas web y en las que aún usan el diseño móvil.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/web_palette.dart';
import '../widgets/gold_button.dart';

enum AlertTone { success, error, warning, info }

extension _ToneStyle on AlertTone {
  Color get color => switch (this) {
    AlertTone.success => WebPalette.emerald,
    AlertTone.error => WebPalette.danger,
    AlertTone.warning => WebPalette.amber,
    AlertTone.info => WebPalette.gold,
  };

  IconData get icon => switch (this) {
    AlertTone.success => Icons.check_circle_rounded,
    AlertTone.error => Icons.error_rounded,
    AlertTone.warning => Icons.warning_amber_rounded,
    AlertTone.info => Icons.info_rounded,
  };
}

class _ToastData {
  final int id;
  final String? title;
  final String message;
  final AlertTone tone;
  final Duration duration;
  _ToastData(this.id, this.title, this.message, this.tone, this.duration);
}

class _DialogData {
  final String title;
  final String message;
  final AlertTone tone;
  final String okText;
  final String? cancelText;
  final bool destructive;
  final bool dismissible;
  final IconData? icon;
  final Completer<bool> completer = Completer<bool>();
  _DialogData({
    required this.title,
    required this.message,
    required this.tone,
    required this.okText,
    required this.cancelText,
    required this.destructive,
    required this.dismissible,
    required this.icon,
  });
}

class _AlertsController extends ChangeNotifier {
  final List<_ToastData> toasts = [];
  final List<_DialogData> dialogs = []; // cola; se muestra el primero
  int _seq = 0;

  void addToast(String? title, String message, AlertTone tone, Duration d) {
    // Si el mismo aviso ya está visible, no se repite.
    if (toasts.any((t) => t.title == title && t.message == message)) return;
    toasts.add(_ToastData(_seq++, title, message, tone, d));
    if (toasts.length > 4) toasts.removeAt(0);
    notifyListeners();
  }

  void removeToast(int id) {
    toasts.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  Future<bool> addDialog(_DialogData d) {
    dialogs.add(d);
    notifyListeners();
    return d.completer.future;
  }

  void closeDialog(_DialogData d, bool result) {
    if (!d.completer.isCompleted) d.completer.complete(result);
    dialogs.remove(d);
    notifyListeners();
  }
}

class WebAlerts {
  WebAlerts._();

  static final _AlertsController _ctrl = _AlertsController();

  /// Aviso no bloqueante.
  static void toast(
    String message, {
    String? title,
    AlertTone tone = AlertTone.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final extra = Duration(milliseconds: (message.length * 25).clamp(0, 4000));
    _ctrl.addToast(title, message, tone, duration + extra);
  }

  /// Modal. Devuelve true si se aceptó.
  static Future<bool> dialog({
    required String title,
    required String message,
    AlertTone tone = AlertTone.info,
    String okText = 'Entendido',
    String? cancelText,
    bool destructive = false,
    bool dismissible = true,
    IconData? icon,
  }) {
    return _ctrl.addDialog(
      _DialogData(
        title: title,
        message: message,
        tone: tone,
        okText: okText,
        cancelText: cancelText,
        destructive: destructive,
        dismissible: dismissible,
        icon: icon,
      ),
    );
  }
}

/// Capa que pinta toasts y modales. Se monta una vez en el builder de la app.
class WebAlertsHost extends StatelessWidget {
  const WebAlertsHost({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WebAlerts._ctrl,
      builder: (context, _) {
        final ctrl = WebAlerts._ctrl;
        final narrow = MediaQuery.sizeOf(context).width < 600;
        final dialog = ctrl.dialogs.isEmpty ? null : ctrl.dialogs.first;

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              if (dialog != null)
                Positioned.fill(
                  child: _AlertDialogView(
                    key: ObjectKey(dialog),
                    data: dialog,
                    onClose: (r) => ctrl.closeDialog(dialog, r),
                  ),
                ),
              Positioned(
                top: narrow ? null : 20,
                bottom: narrow ? 16 : null,
                right: 16,
                left: narrow ? 16 : null,
                child: SizedBox(
                  width: narrow ? null : 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final t in ctrl.toasts)
                        _ToastView(
                          key: ValueKey(t.id),
                          data: t,
                          onClose: () => ctrl.removeToast(t.id),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────────── Toast ─────────────────────────────

class _ToastView extends StatefulWidget {
  final _ToastData data;
  final VoidCallback onClose;
  const _ToastView({super.key, required this.data, required this.onClose});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..forward();
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.data.duration,
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _life.forward().whenComplete(() {
      if (_life.value >= 1) _close();
    });
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    await _enter.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _enter.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.data.tone;
    final curve = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);

    return SizeTransition(
      sizeFactor: curve,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.25, 0),
            end: Offset.zero,
          ).animate(curve),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MouseRegion(
              onEnter: (_) => _life.stop(),
              onExit: (_) {
                if (!_closing) {
                  _life.forward().whenComplete(() {
                    if (_life.value >= 1) _close();
                  });
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xE6121219),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: tone.color.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: tone.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  tone.icon,
                                  color: tone.color,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (widget.data.title != null) ...[
                                        Text(
                                          widget.data.title!,
                                          style: WebPalette.body(
                                            14.5,
                                            weight: FontWeight.w700,
                                            color: WebPalette.text,
                                            height: 1.3,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                      ],
                                      Text(
                                        widget.data.message,
                                        style: WebPalette.body(
                                          13.5,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Sin tooltip: esta capa está fuera del Navigator
                              // y no tiene Overlay donde dibujarlo.
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: _close,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: WebPalette.textFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _life,
                          builder: (context, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: 1 - _life.value,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      tone.color.withValues(alpha: 0.4),
                                      tone.color,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Modal ─────────────────────────────

class _AlertDialogView extends StatefulWidget {
  final _DialogData data;
  final ValueChanged<bool> onClose;
  const _AlertDialogView({
    super.key,
    required this.data,
    required this.onClose,
  });

  @override
  State<_AlertDialogView> createState() => _AlertDialogViewState();
}

class _AlertDialogViewState extends State<_AlertDialogView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();
  final FocusNode _focus = FocusNode();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _close(bool result) async {
    if (_closing) return;
    _closing = true;
    await _c.reverse();
    widget.onClose(result);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final accent = d.destructive ? WebPalette.danger : d.tone.color;
    final fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    final pop = CurvedAnimation(
      parent: _c,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          _close(false);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _close(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Fondo desenfocado
          Positioned.fill(
            child: GestureDetector(
              onTap: d.dismissible ? () => _close(false) : null,
              child: FadeTransition(
                opacity: fade,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.0).animate(pop),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
                      decoration: BoxDecoration(
                        color: WebPalette.bgElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: WebPalette.glassBorder),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 60,
                            spreadRadius: -10,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _IconHalo(icon: d.icon ?? d.tone.icon, color: accent),
                          const SizedBox(height: 20),
                          Text(
                            d.title,
                            textAlign: TextAlign.center,
                            style: WebPalette.display(
                              22,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            d.message,
                            textAlign: TextAlign.center,
                            style: WebPalette.body(15, height: 1.55),
                          ),
                          const SizedBox(height: 26),
                          Row(
                            children: [
                              if (d.cancelText != null) ...[
                                Expanded(
                                  child: _SecondaryButton(
                                    label: d.cancelText!,
                                    onTap: () => _close(false),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: d.destructive
                                    ? _DangerButton(
                                        label: d.okText,
                                        onTap: () => _close(true),
                                      )
                                    : GoldButton(
                                        label: d.okText,
                                        onPressed: () => _close(true),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            d.cancelText != null
                                ? 'Enter para confirmar · Esc para cancelar'
                                : 'Presiona Enter o Esc para cerrar',
                            style: WebPalette.body(
                              11.5,
                              color: WebPalette.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconHalo extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _IconHalo({required this.icon, required this.color});

  @override
  State<_IconHalo> createState() => _IconHaloState();
}

class _IconHaloState extends State<_IconHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.12),
          border: Border.all(
            color: widget.color.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.15 + 0.2 * _c.value),
              blurRadius: 18 + 16 * _c.value,
            ),
          ],
        ),
        child: child,
      ),
      child: Icon(widget.icon, color: widget.color, size: 36),
    );
  }
}

class _SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
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
          duration: const Duration(milliseconds: 180),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: _hover ? 0.09 : 0.04),
            border: Border.all(color: WebPalette.glassBorder),
          ),
          child: Text(
            widget.label,
            style: WebPalette.body(
              15,
              weight: FontWeight.w700,
              color: WebPalette.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _DangerButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _DangerButton({required this.label, required this.onTap});

  @override
  State<_DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<_DangerButton> {
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
          duration: const Duration(milliseconds: 180),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF7A7E), WebPalette.danger],
            ),
            boxShadow: [
              BoxShadow(
                color: WebPalette.danger.withValues(alpha: _hover ? 0.5 : 0.25),
                blurRadius: _hover ? 26 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: WebPalette.body(
              15,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
