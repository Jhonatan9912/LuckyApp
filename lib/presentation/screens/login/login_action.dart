// lib/presentation/screens/login/login_action.dart
//
// Lógica de inicio de sesión compartida entre la app móvil y la web.
// Cada pantalla solo pinta la UI; el flujo (API, sesión, navegación) vive aquí.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:base_app/core/services/secure_storage.dart';
import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/data/api/auth_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/presentation/providers/notifications_provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

/// Ejecuta el login con teléfono y contraseña.
/// [setLoading] permite a la pantalla mostrar su propio estado de carga.
Future<void> performLogin(
  BuildContext context, {
  required String phone,
  required String password,
  required void Function(bool loading) setLoading,
  required bool Function() isMounted,
}) async {
  final authApi = context.read<AuthApi>();
  final session = context.read<SessionManager>();
  final pass = password;

  final ctx = context;
  final subs = ctx.read<SubscriptionProvider>();
  final notifs = ctx.read<NotificationsProvider>(); // capturado una sola vez
  final navigator = Navigator.of(ctx, rootNavigator: true);

  FocusScope.of(ctx).unfocus();

  if (phone.isEmpty || pass.isEmpty) {
    if (!ctx.mounted) return;
    await AppDialogs.warning(
      context: ctx,
      title: 'Validación',
      message: 'Ingresa tu teléfono y contraseña.',
    );
    return;
  }

  setLoading(true);
  try {
    debugPrint('[LOGIN] 1. llamando API loginWithPhone...');
    final json = await authApi
        .loginWithPhone(phone: phone, password: pass)
        .timeout(const Duration(seconds: 12));

    // Access token
    var token = (json['access_token'] ?? json['token'] ?? json['jwt'] ?? '')
        .toString()
        .trim();
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    if (token.isEmpty) {
      throw AuthException('Token no recibido del servidor');
    }

    // Refresh token (opcional)
    final refresh = (json['refresh_token'] ?? json['refreshToken'])
        ?.toString()
        .trim();

    // Usuario
    int? userId, roleId;
    if (json['user'] is Map) {
      final user = (json['user'] as Map).cast<String, dynamic>();
      userId = (user['id'] as num?)?.toInt();
      roleId = (user['role_id'] as num?)?.toInt();
    } else {
      userId = (json['user_id'] as num?)?.toInt();
      roleId = (json['role_id'] as num?)?.toInt();
    }
    if (userId == null) {
      throw AuthException('No se pudo obtener el ID de usuario');
    }

    // Guardar sesión
    await SecureStorage.saveToken(token).catchError((e) {
      debugPrint('[LOGIN] SecureStorage error: $e');
    });
    await session.saveSession(
      token: token,
      refreshToken: (refresh != null && refresh.isNotEmpty) ? refresh : null,
      userId: userId,
      roleId: roleId,
    );

    // Registrar/actualizar el device_token en tu backend
    unawaited(notifs.onUserAuthenticated());

    // Verifica persistencia
    final saved = await session.getToken();
    if (saved == null || saved.isEmpty) {
      throw AuthException('No se pudo persistir la sesión local');
    }

    // Refresca estado de suscripciones (no afecta sesión)
    try {
      await subs.refresh(force: true);
    } catch (e) {
      debugPrint('[LOGIN] subs.refresh error: $e');
    }

    if (!ctx.mounted) return;

    // Mensaje amigable (no bloquea navegación)
    unawaited(() async {
      if (!ctx.mounted) return;
      try {
        await AppDialogs.success(
          context: ctx,
          title: '¡Bienvenido!',
          message: 'Inicio de sesión exitoso.',
          okText: 'Continuar',
        );
      } catch (_) {}
    }());

    // Navegación inmediata
    final target = (roleId == 1) ? '/admin' : '/dashboard';
    navigator.pushNamedAndRemoveUntil(target, (_) => false);
  } on AuthException catch (e) {
    if (!ctx.mounted) return;
    await AppDialogs.error(
      context: ctx,
      title: 'Error de autenticación',
      message: e.message,
    );
  } on TimeoutException {
    if (!ctx.mounted) return;
    await AppDialogs.error(
      context: ctx,
      title: 'Tiempo agotado',
      message: 'El servidor tardó demasiado. Intenta de nuevo.',
    );
  } catch (e) {
    if (!ctx.mounted) return;
    await AppDialogs.error(
      context: ctx,
      title: 'Error',
      message: 'Error inesperado al iniciar sesión',
    );
  } finally {
    if (isMounted()) setLoading(false);
  }
}
