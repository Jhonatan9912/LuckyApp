import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'presentation/screens/paywall/paywall_screen.dart';

import 'data/api/api_service.dart';
import 'data/repositories/user_repository_impl.dart';
import 'domain/usecases/register_user_usecase.dart';
import 'presentation/providers/register_provider.dart';

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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ⚙️ RevenueCat
const _rcAndroidSdkKey = 'goog_UeszbzWntJSeRevMPKysmcHGrlA';
const _appUserNamespace = 'cm_apuestas'; // debe coincidir con tu backend

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupLogging();

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
            session: SessionManager(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ReferralProvider(api: buildReferralsApi())..load(),
        ),
      ],
      child: const BaseApp(),
    ),
  );

  // 🔧 Configura RevenueCat a través del provider y hace un refresh inicial
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final subs = navigatorKey.currentContext!.read<SubscriptionProvider>();
    await Purchases.setLogLevel(LogLevel.debug); // logs en debug
    await subs.configureRC(apiKey: _rcAndroidSdkKey); // SIN appUserId aún
    await subs.refresh(force: true);

    // 🔔 Listener con debounce para evitar parpadeo
    DateTime? lastUpdate;
    Purchases.addCustomerInfoUpdateListener((ci) async {
      final now = DateTime.now();
      if (lastUpdate != null &&
          now.difference(lastUpdate!) < const Duration(seconds: 2)) {
        return; // Ignora updates muy seguidos
      }
      lastUpdate = now;

      await subs.refresh(force: true);
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

/// Llama esto justo después del login exitoso (donde YA tienes el userId).
Future<void> setRevenueCatUser(int userId) async {
  final appUserId = '$_appUserNamespace:$userId';
  await Purchases.logIn(appUserId);
  // Refresca el provider inmediatamente
  final subs = navigatorKey.currentContext?.read<SubscriptionProvider>();
  if (subs != null) await subs.refresh(force: true);
}

/// Llama esto cuando el usuario cierra sesión.
Future<void> clearRevenueCatUser() async {
  await Purchases.logOut();
  final subs = navigatorKey.currentContext?.read<SubscriptionProvider>();
  if (subs != null) subs.clear();
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
      },
    );
  }
}
