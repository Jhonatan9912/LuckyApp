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
const _appUserNamespace =
    'cm_apuestas'; // ← tu namespace (debe coincidir con el backend)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // necesario para llamadas async antes de runApp
  _setupLogging();
  await _initRevenueCat(); // inicializa RevenueCat una sola vez

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
}

void _setupLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '${record.level.name}: ${record.loggerName}: ${record.time}: ${record.message}',
    );
  });
}

Future<void> _initRevenueCat() async {
  await Purchases.setLogLevel(LogLevel.debug);        // logs en debug
  final configuration = PurchasesConfiguration(_rcAndroidSdkKey);
  // En versiones nuevas, RevenueCat completa las compras por defecto.
  // Si tu SDK soporta la API nueva y quieres ser explícito, puedes usar:
  // configuration.purchasesAreCompletedBy = PurchasesAreCompletedBy.revenueCat;
  await Purchases.configure(configuration);
}


/// Llama esto cuando YA tengas el userId (por ejemplo, justo después del login exitoso)
Future<void> setRevenueCatUser(int userId) async {
  await Purchases.logIn('$_appUserNamespace:$userId');
}

/// Llama esto cuando cierres sesión en tu app
Future<void> clearRevenueCatUser() async {
  await Purchases.logOut();
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

      // 👇 opcional: fuerza español Colombia en toda la app
      locale: const Locale('es', 'CO'),

      // 👇 necesario para que showDatePicker tenga textos/formatos
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
