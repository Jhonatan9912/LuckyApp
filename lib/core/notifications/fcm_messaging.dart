// lib/core/notifications/fcm_messaging.dart
//
// Inicializa Firebase Messaging, gestiona permisos, obtiene/renueva el token,
// y muestra notificaciones locales cuando llega un push en foreground.
// Conecta taps (foreground/background/terminated) al NotificationRouter.

import 'dart:async';
import 'dart:convert'; // <-- para jsonDecode
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:base_app/core/notifications/notification_router.dart';

/// Canal de notificaciones para Android (debe ser estable; no lo cambies luego).
const String _kAndroidChannelId = 'default_high_importance_channel';
const String _kAndroidChannelName = 'Notificaciones';
const String _kAndroidChannelDescription = 'Notificaciones generales de la app';

/// Handler de MENSAJES EN SEGUNDO PLANO (background/terminated).
/// Debe ser TOP-LEVEL y con vm:entry-point para que Android/iOS lo invoquen.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // debugPrint('[FCM][BG] Data: ${message.data}');
}

/// Clase Singleton para orquestar FCM + notificaciones locales.
class FcmMessaging with WidgetsBindingObserver {
  FcmMessaging._internal();
  static final FcmMessaging _instance = FcmMessaging._internal();
  static FcmMessaging get I => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Stream con los mensajes recibidos en FOREGROUND (útil para UI reactiva).
  final StreamController<RemoteMessage> _foregroundMessagesCtrl =
      StreamController.broadcast();
  Stream<RemoteMessage> get onForegroundMessage =>
      _foregroundMessagesCtrl.stream;

  /// Último token conocido (puede ser null si el usuario no aceptó permisos).
  String? _currentToken;
  String? get currentToken => _currentToken;

  NotificationRouter? _router;

  /// Adjunta el navigator para poder navegar al tocar notificaciones.
  void attachNavigator(GlobalKey<NavigatorState> navigatorKey) {
    _router = NotificationRouter(navigatorKey: navigatorKey);
  }

  /// Inicializa Firebase, permisos, canales y listeners.
  Future<void> initialize() async {
    if (_initialized) return;
    WidgetsBinding.instance.addObserver(this);

    // 1) Firebase App
    await _ensureFirebase();

    // 2) Configuración de plugin local notifications
    await _initLocalNotifications();

    // 3) Registrar background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 4) Pedir permisos de notificación (plataforma)
    await _requestNotificationPermissions();

    // 5) Obtener token inicial
    _currentToken = await _messaging.getToken();
    if (kDebugMode) {
      debugPrint('[FCM] initial token: $_currentToken');
    }

    // 6) Suscribirse a onTokenRefresh
    _messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
      if (kDebugMode) {
        debugPrint('[FCM] token refreshed: $token');
      }
      // (el NotificationsProvider re-registrará en backend)
    });

    // 7) Listener de mensajes en FOREGROUND:
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _foregroundMessagesCtrl.add(message);

      // Mostrar notificación local cuando la app está en primer plano
      await _showLocalNotificationFromMessage(message);
    });

    // 8) Click en notificación que abre la app desde BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      if (kDebugMode) {
        debugPrint('[FCM] onMessageOpenedApp data=${message.data}');
      }
      if (_router != null) {
        await _router!.handle(message.data);
      }
    });

    // 9) Mensaje que abrió la app desde estado TERMINATED
    final initialMsg = await _messaging.getInitialMessage();
    if (initialMsg != null) {
      if (kDebugMode) {
        debugPrint('[FCM] getInitialMessage data=${initialMsg.data}');
      }
      if (_router != null) {
        await _router!.handle(initialMsg.data);
      }
    }

    _initialized = true;
  }

  /// Limpia recursos
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _foregroundMessagesCtrl.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si necesitas reaccionar al ciclo de vida, hazlo aquí.
  }

  // ================== Helpers internos ==================

  Future<void> _ensureFirebase() async {
    try {
      Firebase.app();
    } catch (_) {
      await Firebase.initializeApp();
    }
  }

  Future<void> _initLocalNotifications() async {
    // Android: canal
    const AndroidNotificationChannel androidChannel = AndroidNotificationChannel(
      _kAndroidChannelId,
      _kAndroidChannelName,
      description: _kAndroidChannelDescription,
      importance: Importance.high,
      playSound: true,
    );

    // Inicializaciones por plataforma
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // icono blanco/transparente recomendado
    const DarwinInitializationSettings initIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: initAndroid,
      iOS: initIOS,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (kDebugMode) {
          debugPrint('[LOCAL] onDidReceiveNotificationResponse payload=${response.payload}');
        }
        if (_router != null &&
            response.payload != null &&
            response.payload!.isNotEmpty) {
          final map = _tryDecodeToMap(response.payload!);
          if (map != null) {
            await _router!.handle(map);
          }
        }
      },
    );

    // Crear canal en Android
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Pide permisos (Android 13+/iOS) y registra preferencias de iOS.
  Future<void> _requestNotificationPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isRestricted) {
        await Permission.notification.request();
      }
      return;
    }

    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      if (kDebugMode) {
        debugPrint('[FCM] iOS settings: $settings');
      }
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// Mapea un RemoteMessage a una notificación local visible cuando la app está en primer plano.
  Future<void> _showLocalNotificationFromMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? 'Notificación';
    final body = notification?.body ?? '';

    final androidDetails = AndroidNotificationDetails(
      _kAndroidChannelId,
      _kAndroidChannelName,
      channelDescription: _kAndroidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iOSDetails);

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _local.show(
      id,
      title,
      body,
      details,
      // Si quisieras rutear taps de locales, envía aquí un JSON como payload.
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
  }

  /// Intenta decodificar un String a `Map<String, dynamic>` suponiendo JSON.
  Map<String, dynamic>? _tryDecodeToMap(String raw) {
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

}
