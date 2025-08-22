// lib/core/ui/dialogs.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';

class AppDialogs {
  static Future<void> success({
    required BuildContext context,
    required String title,
    required String message,
    String okText = 'OK',
    VoidCallback? onOk,
  }) async {
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
    final theme = Theme.of(context);
    final Color okColor = destructive
        ? Colors.red
        : theme.colorScheme.primary;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // que no se cierre tocando fuera
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              style: FilledButton.styleFrom(
                backgroundColor: okColor,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(okText),
            ),
          ],
        );
      },
    );

    return result == true;
  }
}
