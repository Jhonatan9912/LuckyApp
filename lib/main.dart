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
    api: ReferralsApi(
      baseUrl: Env.apiBaseUrl,
      session: session,  // ya lo estabas enviando
    ),
    session: session,     // ← AHORA SÍ lo pasamos al provider
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
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFB8860B),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFFFF3C0),
          onPrimaryContainer: Color(0xFF3A2800),
          secondary: Color(0xFF8B6914),
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFFFE8A0),
          onSecondaryContainer: Color(0xFF2A1C00),
          surface: Colors.white,
          onSurface: Color(0xFF1A1A1A),
          surfaceContainerHighest: Color(0xFFF5F5F5),
          onSurfaceVariant: Color(0xFF5A4A20),
          background: Colors.white,
          onBackground: Color(0xFF1A1A1A),
          error: Color(0xFFB00020),
          onError: Colors.white,
          outline: Color(0xFFD4AF37),
          outlineVariant: Color(0xFFEAD88A),
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0A),
          foregroundColor: Color(0xFFD4AF37),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFFD4AF37)),
          actionsIconTheme: IconThemeData(color: Color(0xFFD4AF37)),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
          margin: EdgeInsets.zero,
          shadowColor: Color(0x22D4AF37),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0xFFEAD88A), width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: const Color(0xFF0A0A0A),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB8860B),
            side: const BorderSide(color: Color(0xFFD4AF37)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: const Color(0xFF0A0A0A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEAD88A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEAD88A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF8B6914)),
          hintStyle: const TextStyle(color: Color(0xFFC8A84B)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFFFF9E0),
          selectedColor: const Color(0xFFD4AF37),
          labelStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFEAD88A)),
          ),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFEAD88A)),
        iconTheme: const IconThemeData(color: Color(0xFFB8860B)),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF4A3800),
          unselectedLabelColor: Color(0xFF8B7030),
          indicatorColor: Color(0xFFD4AF37),
          dividerColor: Color(0xFFEAD88A),
          labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0xFFEAD88A)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF2A2000),
          contentTextStyle: TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFFB8860B),
          textColor: Color(0xFF1A1A1A),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFD4AF37)),
        ),
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
