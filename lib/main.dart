// lib/main.dart
import 'dart:async'; // por si luego usamos unawaited

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'presentation/screens/paywall/paywall_screen.dart';

import 'data/api/api_service.dart';
import 'data/repositories/user_repository_impl.dart';
import 'domain/usecases/register_user_usecase.dart';
import 'presentation/providers/register_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'presentation/screens/splash/splash_screen.dart';
import 'presentation/screens/login/login_screen.dart';
import 'presentation/screens/reset_password/set_new_password_screen.dart';
import 'presentation/screens/register/register_screen.dart';
import 'presentation/screens/admin_dashboard/admin_dashboard_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';

import 'presentation/screens/faq/faq_reset_password_screen.dart';
import 'presentation/screens/faq/faq_play_screen.dart';

import 'package:base_app/data/api/subscriptions_api.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';
import 'package:base_app/core/config/env.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:base_app/data/api/referrals_api.dart';
import 'package:base_app/presentation/providers/payouts_provider.dart';
import 'package:base_app/data/api/payouts_api.dart';
import 'presentation/screens/faq/subscriptions/subscriptions_faq_screen.dart';
import 'package:base_app/core/network/api_client.dart';
import 'package:base_app/data/api/auth_api.dart';
import 'presentation/screens/faq/referrals/referrals_faq_screen.dart';
import 'core/notifications/fcm_messaging.dart';
import 'presentation/providers/notifications_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  _setupLogging();

  // Locale por defecto para Intl y formatos
  Intl.defaultLocale = 'es_CO';

  // Instancias compartidas
  final session = SessionManager();
  final apiClient = ApiClient(baseUrl: Env.apiBaseUrl, session: session);
  final authApi = AuthApi(baseUrl: Env.apiBaseUrl, apiClient: apiClient);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RegisterProvider(
            RegisterUserUseCase(UserRepositoryImpl(api: ApiService())),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SubscriptionProvider(
            api: SubscriptionsApi(baseUrl: Env.apiBaseUrl),
            session: session,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ReferralProvider(
            api: ReferralsApi(baseUrl: Env.apiBaseUrl, session: session),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => PayoutsProvider(
            api: PayoutsApi(baseUrl: Env.apiBaseUrl, session: session),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => buildNotificationsProvider(
            apiClient: apiClient,
            session: session,
          ),
        ),

        // instancias crudas
        Provider<AuthApi>.value(value: authApi),
        Provider<ApiClient>.value(value: apiClient),
        Provider<SessionManager>.value(value: session),
      ],
      child: const BaseApp(),
    ),
  );

  // >>> pega esto justo DESPUÉS de runApp(...)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    // Captura providers ANTES de cualquier await (evita el lint)
    final subs = ctx.read<SubscriptionProvider>();
    final referrals = ctx.read<ReferralProvider>();
    final notifs = ctx.read<NotificationsProvider>();

    // Ejecuta en microtarea para no retrasar el frame actual
    Future.microtask(() async {
      try {
        // Inicializa FCM (puede tardar un poco). Si falla, no rompe la app.
        await FcmMessaging.I.initialize();
        final t = await FirebaseMessaging.instance.getToken();
        debugPrint('[MAIN] FCM token (direct): $t');

        // Lanza operaciones sin bloquear (no usamos await)
        unawaited(subs.configureBilling());
        unawaited(subs.refresh(force: true));
        unawaited(referrals.load(refresh: true));

        // Notificaciones: init + posible registro de token
        unawaited(() async {
          try {
            await notifs.init();
            await notifs.onUserAuthenticated();
          } catch (e) {
            debugPrint('[notifs] init/onUserAuthenticated error: $e');
          }
        }());
      } catch (e) {
        debugPrint('[bootstrap] FCM initialize error: $e');
      }
    });
  });
}

void _setupLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '${record.level.name}: ${record.loggerName}: ${record.time}: ${record.message}',
    );
  });
}

class BaseApp extends StatelessWidget {
  const BaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tu Rifa App',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/registro': (context) => const RegisterScreen(),
        '/nueva-contrasena': (context) => const SetNewPasswordScreen(),
        '/admin': (_) => const AdminDashboardScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/faq/restablecer': (_) => const FaqResetPasswordScreen(),
        '/faq/juego': (_) => const FaqPlayScreen(),
        '/pro': (_) => const PaywallScreen(),
        '/faq/pro': (_) => const SubscriptionsFaqScreen(),
        '/faq/referidos': (_) => const ReferralsFaqScreen(),
      },
    );
  }
}
