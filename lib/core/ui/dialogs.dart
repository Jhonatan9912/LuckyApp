// lib/core/ui/dialogs.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:base_app/web/alerts/web_alerts.dart';

class AppDialogs {
  static Future<void> success({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'OK',
    VoidCallback? onOk,
  }) async {
    if (kIsWeb) {
      // En web el éxito no interrumpe: aviso flotante.
      WebAlerts.toast(message, title: title, tone: AlertTone.success);
      onOk?.call();
      return;
    }
    final ctx = context;
    return AwesomeDialog(
      context: ctx,
      dialogType: DialogType.success,
      animType: AnimType.scale,
      title: title,
      desc: message,
      btnOkText: okText,
      btnOkColor: Colors.green,
      btnOkOnPress: onOk,
      headerAnimationLoop: false,
      dismissOnBackKeyPress: true,
      dismissOnTouchOutside: true,
    ).show();
  }

  static Future<void> error({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'Entendido',
    VoidCallback? onOk,
  }) async {
    if (kIsWeb) {
      await WebAlerts.dialog(
        title: title,
        message: message,
        tone: AlertTone.error,
        okText: okText,
      );
      onOk?.call();
      return;
    }
    final ctx = context;
    return AwesomeDialog(
      context: ctx,
      dialogType: DialogType.error,
      animType: AnimType.rightSlide,
      title: title,
      desc: message,
      btnOkText: okText,
      btnOkColor: Colors.red,
      btnOkOnPress: onOk,
      headerAnimationLoop: false,
      dismissOnBackKeyPress: true,
      dismissOnTouchOutside: true,
    ).show();
  }

  static Future<void> warning({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'OK',
  }) async {
    if (kIsWeb) {
      WebAlerts.toast(message, title: title, tone: AlertTone.warning);
      return;
    }
    final ctx = context;
    return AwesomeDialog(
      context: ctx,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: title,
      desc: message,
      btnOkText: okText,
      btnOkColor: Colors.amber[800],
      btnOkOnPress: () {},
      headerAnimationLoop: false,
      dismissOnBackKeyPress: true,
      dismissOnTouchOutside: true,
    ).show();
  }

  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'Confirmar',
    String cancelText = 'Cancelar',
    bool destructive = false, // pinta el botón OK en rojo si es destructivo
    IconData? icon,
  }) async {
    if (kIsWeb) {
      return WebAlerts.dialog(
        title: title,
        message: message,
        tone: AlertTone.info,
        okText: okText,
        cancelText: cancelText,
        destructive: destructive,
        icon: icon ?? Icons.help_outline_rounded,
      );
    }
    final theme = Theme.of(context);
    final Color okColor = destructive ? Colors.red : theme.colorScheme.primary;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // que no se cierre tocando fuera
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: okColor.withValues(alpha: 0.12),
                child: Icon(icon ?? Icons.help_outline, color: okColor),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelText),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: okColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(okText),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  /// Confirmación con el estilo clásico (título, texto, Cancelar / OK) en la app;
  /// en web usa el modal moderno.
  static Future<bool> confirmPlain({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'Aceptar',
    String cancelText = 'Cancelar',
    bool destructive = false,
    IconData? icon,
  }) async {
    if (kIsWeb) {
      return WebAlerts.dialog(
        title: title,
        message: message,
        okText: okText,
        cancelText: cancelText,
        destructive: destructive,
        icon: icon ?? Icons.help_outline_rounded,
      );
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// Muestra un SnackBar en la app; en web lo convierte en aviso flotante moderno.
extension AppSnackBars on ScaffoldMessengerState {
  void showAppSnackBar(SnackBar snack, {AlertTone? tone}) {
    if (!kIsWeb) {
      showSnackBar(snack);
      return;
    }
    final content = snack.content;
    final text = content is Text
        ? (content.data ?? content.textSpan?.toPlainText() ?? '')
        : '';
    if (text.isEmpty) {
      showSnackBar(snack);
      return;
    }
    WebAlerts.toast(
      text,
      tone: tone ?? _guessTone(text, snack.backgroundColor),
    );
  }

  static AlertTone _guessTone(String text, Color? bg) {
    final t = text.toLowerCase();
    const errorHints = [
      'error',
      'no se pudo',
      'no pude',
      'ocurrió',
      'falló',
      'inválid',
      'solo administradores',
    ];
    if (errorHints.any(t.contains)) return AlertTone.error;
    if (bg != null && bg.r > 0.5 && bg.g < 0.4) return AlertTone.error;
    return AlertTone.success;
  }
}
