// lib/presentation/screens/splash/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/core/services/secure_storage.dart';
import 'package:base_app/data/api/auth_api.dart';

import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authApi = AuthApi(baseUrl: 'http://10.0.2.2:8000');

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // ✅ Capturamos el provider ANTES de cualquier await
    final subs = context.read<SubscriptionProvider>();

    await Future.delayed(const Duration(milliseconds: 400));

    final session = SessionManager();

    // 1) Token (con migración desde SecureStorage si hace falta)
    String? token = await session.getToken();
    if (token == null || token.isEmpty) {
      final secure = await SecureStorage.getToken();
      if (secure != null && secure.isNotEmpty) {
        await session.saveSession(token: secure);
        token = secure;
      }
    }

    if (!mounted) return;

    if (token == null || token.isEmpty) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    // 2) Refrescar perfil para tomar role_id actual
    int? roleId;
    try {
      final me = await _authApi.me(token); // { ok:true, id, role_id, ... }
      roleId = (me['role_id'] as num?)?.toInt();

      final userId = (me['id'] as num?)?.toInt();
      await session.saveSession(roleId: roleId, userId: userId);

      // ✅ Usamos la referencia (sin tocar context tras awaits)
      await subs.refresh(force: true);
    } catch (_) {
      await SecureStorage.clear();
      await session.clear();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    if (!mounted) return;

    // 3) Ruta por rol (admin = 1)
    final target = (roleId == 1) ? '/admin' : '/dashboard';
    Navigator.pushReplacementNamed(context, target);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
