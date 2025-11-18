import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:base_app/presentation/screens/dashboard/logic/sound_helper.dart';
import 'package:base_app/data/api/games_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/domain/auth/auth_repository.dart';
import 'dart:math';

/// Estados/Resultados para operaciones clave del tablero
enum GenerateState { ok, error }

class ReserveOutcome {
  final bool ok;
  final bool gameCompleted; // true si al confirmar, el juego se completó
  final String? message; // mensaje técnico u orientativo
  final String? code; // códigos como CONFLICT, GAME_SWITCHED, NETWORK_ERROR
  final int? status; // HTTP status si aplica
  const ReserveOutcome({
    required this.ok,
    this.gameCompleted = false,
    this.message,
    this.code,
    this.status,
  });
}

/// "Controlador" con ChangeNotifier para aislar la lógica de UI.
///
/// - No muestra diálogos ni usa BuildContext.
/// - Expone estado y métodos async; la Vista decide cómo presentar mensajes.
class DashboardController extends ChangeNotifier {
  // Dependencias
  final GamesApi _gamesApi;
  final AuthRepository _authRepo;
  final SessionManager _session;
  final Set<int> _shownNotifIds = <int>{};

  DashboardController({
    required GamesApi gamesApi,
    required AuthRepository authRepo,
    required SessionManager session,
    int devUserId = 1,
  }) : _gamesApi = gamesApi,
       _authRepo = authRepo,
       _session = session,
       _devUserId = devUserId;

  // ======= Estado observable =======
  List<int> _numbers = List.filled(5, 0);
  bool _animating = false;
  bool _showFinalButtons = false;
  bool _hasPlayedOnce = false;
  bool _hasAdded = false;
  final List<int> _displayedBalls = <int>[];
  bool _showActionIcons = false;
  int? _currentBigBall;
  bool _hasAddedFinal = false;
  bool _saving = false;
  bool _reserving = false;
  bool _sessionReady = false;
  int? _lastReservedUserId;
  int? _gameId; // id del juego actual desde backend
  List<int> _generated = const []; // últimos 5 números generados por /generate
  String? _authToken;
  String? referralCode; // <- se lee desde el UI (_ctrl.referralCode)
  final int _devUserId;
  int? _lastReservedGameId;
  List<int>? _lastReservedNumbers; // números de la última reserva confirmada
  bool _releasedPrevious =
      false; // en este ciclo de add() se liberó una reserva previa
  int? _lastClosedGameId; // id del último juego que quedó cerrado
  int? get lastClosedGameId => _lastClosedGameId;
  int? _userId;
  int? get userId => _userId;
  bool _isPremium = false;
  bool get isPremium => _isPremium;

  // ======= Configuración del juego (3 o 4 cifras) =======
  int _digitsPerBall = 3;          // valor por defecto: 3 cifras

  int get digitsPerBall => _digitsPerBall;

  void setDigitsPerBall(int value) {
    // Solo permitimos 3 o 4 cifras
    if (value != 3 && value != 4) return;

    // Si no cambia, no notifiques
    if (_digitsPerBall == value) return;

    _digitsPerBall = value;
    notifyListeners();
  }


  // ======= Getters públicos =======
  List<int> get numbers => List.unmodifiable(_numbers);
  bool get animating => _animating;
  bool get showFinalButtons => _showFinalButtons;
  bool get hasPlayedOnce => _hasPlayedOnce;
  bool get hasAdded => _hasAdded;
  List<int> get displayedBalls => List.unmodifiable(_displayedBalls);
  bool get showActionIcons => _showActionIcons;
  int? get currentBigBall => _currentBigBall;
  bool get hasAddedFinal => _hasAddedFinal;
  bool get saving => _saving;
  bool get reserving => _reserving;
  bool get sessionReady => _sessionReady;
  int? get gameId => _gameId;
  String? get authToken => _authToken;

  // ======= Historial =======
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> get history => _history;

  bool _isGameClosedLocal(int gid) {
    for (final m in _history) {
      final mid = (m['game_id'] as num?)?.toInt();
      if (mid != gid) continue;
      final status = (m['status'] ?? m['result'] ?? '')
          .toString()
          .toLowerCase();
      final hasWinner =
          m['winning_number'] != null ||
          status.contains('closed') ||
          status.contains('completed') ||
          status.contains('perdido') ||
          status.contains('ganado');
      return hasWinner;
    }
    return false;
  }

  // ======= Helpers internos =======
  bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return true;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= exp;
    } catch (_) {
      return true;
    }
  }

  String _fmtNums(List<int> xs) =>
      xs.map((e) => e.toString().padLeft(_digitsPerBall, '0')).join('-');


  void _setAnimating(bool v) {
    _animating = v;
    notifyListeners();
  }

  void _setShowFinalButtons(bool v) {
    _showFinalButtons = v;
    notifyListeners();
  }

  void _setHasPlayedOnce(bool v) {
    _hasPlayedOnce = v;
    notifyListeners();
  }

  void _setNumbers(List<int> list) {
    _numbers = list;
    notifyListeners();
  }

  void _setCurrentBigBall(int? v) {
    _currentBigBall = v;
    notifyListeners();
  }

  void _setHasAdded(bool v) {
    _hasAdded = v;
    notifyListeners();
  }

  void _setShowActionIcons(bool v) {
    _showActionIcons = v;
    notifyListeners();
  }

  void _setHasAddedFinal(bool v) {
    _hasAddedFinal = v;
    notifyListeners();
  }

  void _setSaving(bool v) {
    _saving = v;
    notifyListeners();
  }

  void _setReserving(bool v) {
    _reserving = v;
    notifyListeners();
  }

  void _setSessionReady(bool v) {
    _sessionReady = v;
    notifyListeners();
  }

  // ======= Sesión =======
  Future<void> initSession() async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      _authToken = null;
      _userId = null;
      _isPremium = false; // 👈 sin sesión, no PRO
      _setSessionReady(false);
      notifyListeners();
      return;
    }

    _authToken = token;
    final dynamic uid = await _session.getUserId();
    if (uid is int) {
      _userId = uid;
    } else if (uid is String) {
      _userId = int.tryParse(uid);
    } else {
      _userId = null;
    }

    // 👇 NUEVO: sincroniza PRO de la sesión (persistido por tu backend tras validar compra)
    final fromSession = await _session.getIsPremium() == true;
    // Solo promociona a PRO si la sesión lo dice; no lo bajes aquí.
    if (fromSession) {
      _isPremium = true;
    }
    // _isPremium se seguirá actualizando por applyPremiumFromStore()

    _setSessionReady(true);
    notifyListeners();
      // 🔴 NUEVO: apenas hay sesión válida, cargo historial y restauro selección
  unawaited(() async {
    await loadHistory();           // primero historial (lo usas para saber si el juego ya cerró)
    await restoreSelectionIfAny(); // luego restaura si la selección sigue vigente
  }());

  }

  Future<void> loadReferralCode() async {
    // ✅ opción 2: factoriza la condición
    final needsInit = !_sessionReady || (_authToken?.isEmpty ?? true);
    if (needsInit) {
      await initSession();
      if (!_sessionReady) {
        referralCode = null;
        notifyListeners();
        return;
      }
    }

    try {
      final profile = await _authRepo.getProfile();
      final code = profile?['public_code']?.toString().trim();
      referralCode = (code != null && code.isNotEmpty) ? code : null;
    } catch (_) {
      referralCode = null;
    }
    notifyListeners();
  }

  Future<void> restoreSelectionIfAny() async {
    // requiere sesión válida
    if (_authToken == null || _authToken!.isEmpty) return;

        final res = await _gamesApi.getMySelection(
      token: _authToken,
      digits: _digitsPerBall,
    );

    if (res['ok'] != true) return;

    final data = (res['data'] as Map<String, dynamic>? ?? {});
    final gid = (data['game_id'] as num?)?.toInt();
    final numsDyn = (data['numbers'] as List?) ?? const [];
    final nums = numsDyn.map((e) => int.parse(e.toString())).toList();

    if (gid == null || nums.length != 5) return;

    // ⛔ No restaurar si ese juego ya cerró (según el historial ya cargado)
    final closed = _history.any((m) {
      final mid = (m['game_id'] as num?)?.toInt();
      if (mid != gid) return false;
      final status = (m['status'] ?? m['result'] ?? '')
          .toString()
          .toLowerCase();
      final hasWinner =
          m['winning_number'] != null ||
          status.contains('closed') ||
          status.contains('completed') ||
          status.contains('perdido') ||
          status.contains('ganado');
      return hasWinner;
    });

    if (closed) {
      _gameId = null;
      _lastReservedGameId = null;
      _lastReservedNumbers = null;
      _displayedBalls.clear();
      _setNumbers(List.filled(5, 0));
      _setHasAdded(false);
      _setHasAddedFinal(false);
      _setShowFinalButtons(false);
      _setHasPlayedOnce(false);
      _setShowActionIcons(false);
      notifyListeners();
      return;
    }

    // ✅ Si el juego sigue abierto, ahora sí restaura la selección
    _gameId = gid;
    _lastReservedGameId = gid;
    _lastReservedNumbers = List<int>.from(nums);

    final uidUsed = (data['user_id_used'] as num?)?.toInt();
    _lastReservedUserId = uidUsed ?? _lastReservedUserId;

    _setNumbers(List<int>.from(nums));
    _displayedBalls
      ..clear()
      ..addAll(nums);

    _setHasAdded(true);
    _setHasAddedFinal(true);
    _setShowActionIcons(true);
    _setShowFinalButtons(true);
    _setHasPlayedOnce(true);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      // Revoca en backend si aplica, pero no bloquees el flujo si falla
      await _authRepo.logout().catchError((_) {});

      // 🔑 Borra SIEMPRE la sesión local (token, userId, roleId)
      await _session.clear();
    } catch (_) {
      // Ignora errores locales para no trabar la UI
    }

    // Limpieza de estado en memoria
    _authToken = null;
    referralCode = null;
    _isPremium = false;
    _lastReservedGameId = null;
    _lastReservedNumbers = null;
    _lastReservedUserId = null;
    _lastClosedGameId = null;

    _notifications = [];
    _unreadCount = 0;
    _history = [];
    _shownNotifIds.clear();

    // Deja la UI en estado inicial
    resetToInitial();
    _setSessionReady(false);
    notifyListeners();
  }

  Future<GenerateState> generateAnimatedNumbers({
    int? avoidGameId, // <- NUEVO: evita generar con este id
    int attempts = 3, // <- NUEVO: reintentos para conseguir id distinto
  }) async {
    if (_animating || _saving || _reserving) return GenerateState.error;

    // 👇 PRE-CHEQUEO: si ya hay selección actual en el juego abierto, muéstrala y no animes
    final String? tokenToUse =
        (_authToken != null && !_isJwtExpired(_authToken!)) ? _authToken : null;
    final int? xUserIdToUse = (tokenToUse == null) ? _devUserId : null;

    if (tokenToUse != null) {
      try {
                final pre = await _gamesApi.getMySelection(
          token: tokenToUse,
          digits: _digitsPerBall,
        );

        if (pre['ok'] == true) {
          final data = (pre['data'] as Map<String, dynamic>? ?? {});
          final gid = (data['game_id'] as num?)?.toInt();
          final nums = ((data['numbers'] as List?) ?? const [])
              .map((e) => int.parse(e.toString()))
              .toList();

          if (gid != null && nums.length == 5) {
            _gameId = gid;
            _lastReservedGameId = gid;
            _lastReservedNumbers = List<int>.from(nums);
            _setNumbers(List<int>.from(nums));
            _displayedBalls
              ..clear()
              ..addAll(nums);

            _setAnimating(false);
            _setShowFinalButtons(true);
            _setHasPlayedOnce(true);
            _setHasAdded(true);
            _setHasAddedFinal(true);
            _setShowActionIcons(true);
            return GenerateState.ok; // ← ya está “bloqueado” por tener 5
          }
        }
      } catch (_) {
        // ignora errores de red aquí; seguimos con la generación normal
      }
    }

    _setAnimating(true);
    _setShowFinalButtons(false);
    _setHasPlayedOnce(true);

    Map<String, dynamic>? data;

    for (var i = 0; i < attempts; i++) {
      final res = await _gamesApi.generate(
        token: tokenToUse,
        xUserId: xUserIdToUse,
        digits: _digitsPerBall, // 👈 3 ó 4
      );

      if (res['ok'] == true) {
        final d = (res['data'] as Map<String, dynamic>? ?? {});
        final gid = (d['game_id'] as num?)?.toInt();
        if (gid != null && (avoidGameId == null || gid != avoidGameId)) {
          data = d;
          break;
        }
      } else {
        _setAnimating(false);
        _setShowFinalButtons(false);
        _setHasPlayedOnce(false);
        return GenerateState.error;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (data == null) {
      _setAnimating(false);
      _setShowFinalButtons(false);
      _setHasPlayedOnce(false);
      return GenerateState.error;
    }

    try {
      _gameId = (data['game_id'] as num).toInt();
      final List<dynamic> nums = data['numbers'] as List<dynamic>;
      _generated = nums.map((e) => int.parse(e.toString())).toList();

      final result = <int>[];
      for (final n in _generated) {
        result.add(n);
        _setNumbers(
          List<int>.from(result)..addAll(List.filled(5 - result.length, 0)),
        );
        await Future.delayed(const Duration(seconds: 1));
      }

      await Future.delayed(const Duration(milliseconds: 300));
      _setAnimating(false);
      _setShowFinalButtons(true);
      return GenerateState.ok;
    } catch (_) {
      _setAnimating(false);
      _setShowFinalButtons(false);
      _setHasPlayedOnce(false);
      return GenerateState.error;
    }
  }

  Future<GenerateState> openFreshGame({int attempts = 3}) async {
    // Antes: final avoid = _lastClosedGameId ?? _lastReservedGameId;
    // Ahora: no evites nada; el backend ya no te devolverá juegos cerrados
    return generateAnimatedNumbers(avoidGameId: null, attempts: attempts);
  }

  // ======= REINTENTAR =======
  Future<void> retry() async {
    _setReserving(false);
    _displayedBalls.clear();
    _setNumbers(List.filled(5, 0));
    _setShowFinalButtons(false);
    _setHasAddedFinal(false);
    _setHasAdded(false);
    _setShowActionIcons(false);
    _setCurrentBigBall(null);

    await generateAnimatedNumbers();
  }

  Future<GenerateState> generateLocalPreview() async {
    if (_animating || _saving || _reserving) return GenerateState.error;

    // Modo demo (FREE): no tocar backend ni asignar gameId
    _gameId = null;
    _setAnimating(true);
    _setShowFinalButtons(false);
    _setHasPlayedOnce(true);

    final rnd = Random();
    final maxValue = pow(10, _digitsPerBall).toInt(); // 1000 o 10000
    _generated = List<int>.generate(5, (_) => rnd.nextInt(maxValue));


    final result = <int>[];
    for (final n in _generated) {
      result.add(n);
      _setNumbers(
        List<int>.from(result)..addAll(List.filled(5 - result.length, 0)),
      );
      await Future.delayed(const Duration(seconds: 1));
    }

    await Future.delayed(const Duration(milliseconds: 300));
    _setAnimating(false);
    _setShowFinalButtons(true);
    return GenerateState.ok;
  }

  // ======= RESERVAR/CONFIRMAR =======
  Future<ReserveOutcome> add() async {
    debugPrint('[ADD] isPremium=$_isPremium, gameId=$_gameId');
    if (_authToken == null || _authToken!.isEmpty) {
      return const ReserveOutcome(
        ok: false,
        code: 'UNAUTHENTICATED',
        message: 'Sesión no válida.',
      );
    }
    if (!_isPremium) {
      return const ReserveOutcome(
        ok: false,
        code: 'NEED_PREMIUM',
        message: 'Necesitas PRO para reservar.',
        status: 403,
      );
    }
    final stillRevealing = _animating || !_showFinalButtons;
    if (_gameId == null) {
      return const ReserveOutcome(
        ok: false,
        code: 'PREVIEW_ONLY',
        message: 'Primero presiona JUGAR para generar una selección.',
        status: 400,
      );
    }

    if (stillRevealing) {
      return const ReserveOutcome(
        ok: false,
        code: 'INVALID_STATE',
        message: 'Aún no hay selección lista.',
      );
    }

    final maxValue = pow(10, _digitsPerBall).toInt() - 1; // 999 o 9999
    final isValid =
        _numbers.length == 5 && _numbers.every((n) => n >= 0 && n <= maxValue);

    if (!isValid) {
      return const ReserveOutcome(
        ok: false,
        code: 'OUT_OF_RANGE',
        message: 'Selección fuera de rango.',
      );
    }

    // 1) Guarda copia de los números de la reserva anterior (si los hay)
    final prevNumbers = (_lastReservedNumbers == null)
        ? null
        : List<int>.from(_lastReservedNumbers!);

    // 2) Libera la reserva previa si existe
    final releaseOutcome = await _releasePreviousIfNeeded();
    if (releaseOutcome != null && !releaseOutcome.ok) {
      return releaseOutcome; // si falló liberar, cortamos aquí
    }

    // Activa modo reservando: oculta botones y resetea tiras
    _setReserving(true);
    _displayedBalls.clear();
    _setShowActionIcons(false);
    _setHasAdded(true);

    // Efecto de "balota grande" (la Vista puede decidir si usa sonido/animación)
    for (final number in _numbers) {
      _setCurrentBigBall(number);

      // 🔊 reproducir pop aquí
      await SoundHelper.playPopSound();

      await Future.delayed(const Duration(seconds: 1));
      _setCurrentBigBall(null);
      _displayedBalls.add(number);
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _setShowActionIcons(true);

    // Si el token está vencido, no intentes commit
    if (_isJwtExpired(_authToken!)) {
      _setReserving(false);
      return const ReserveOutcome(
        ok: false,
        code: 'TOKEN_EXPIRED',
        message: 'Tu sesión venció.',
      );
    }

    // Guardando en backend
    _setSaving(true);
    final res = await _gamesApi.commit(
      gameId: _gameId!,
      numbers: _numbers,
      token: _authToken, // ✅ usar Authorization
      xUserId: null, // ❌ no enviar X-USER-ID
    );

    _setSaving(false);
    _setReserving(false);

    if (res['ok'] == true) {
      final data = (res['data'] as Map<String, dynamic>? ?? {});
      _setHasAddedFinal(true);

      _lastReservedGameId = _gameId;
      _lastReservedNumbers = List<int>.from(_numbers);
      final userIdUsed = (data['user_id_used'] as num?)?.toInt();
      _lastReservedUserId = userIdUsed ?? _lastReservedUserId;

      // lo que reporta el backend
      final completed =
          data['game_completed'] == true || res['game_completed'] == true;

      // refresca historial y calcula cierre local ANTES de tocar _gameId
      final gid = _gameId; // 👈 guardar referencia
      await loadHistory();
      final closedNow = (gid != null) && _isGameClosedLocal(gid);

      final finalCompleted = completed || closedNow;
      if (finalCompleted) {
        _lastClosedGameId = gid; // <- NUEVO: recuerda cuál se cerró
        _gameId = null;
        _lastReservedGameId = null;
        _lastReservedNumbers = null;
      } else {
        _lastClosedGameId = null; // por si venía seteado de antes
      }

      if (_releasedPrevious && prevNumbers != null) {
        _releasedPrevious = false;
        return ReserveOutcome(
          ok: true,
          gameCompleted: finalCompleted,
          code: 'REPLACED',
          message:
              'Se reemplazaron ${_fmtNums(prevNumbers)} por ${_fmtNums(_numbers)}.',
        );
      }
      _releasedPrevious = false;
      return ReserveOutcome(ok: true, gameCompleted: finalCompleted);
    }

    final code = (res['code'] ?? '').toString();
    final msg = (res['message'] ?? 'No se pudo guardar la selección.')
        .toString();
    final status = res['status'] as int?;

if (code == 'GAME_SWITCHED') {
  // Reset mínimo para permitir volver a jugar
  _setHasAdded(false);
  _setHasAddedFinal(false);
  _displayedBalls.clear();
  _setShowActionIcons(false);
  _setNumbers(List.filled(5, 0));
  _setShowFinalButtons(false);
  _setHasPlayedOnce(false);

  _gameId = null;
  _lastReservedGameId = null;
  _lastReservedNumbers = null;

  return ReserveOutcome(
    ok: false,
    code: 'GAME_SWITCHED',
    message: 'El juego cambió porque se completó. Vuelve a jugar.',
    status: status,
  );

} else if (code == 'CONFLICT' || status == 409) {
  _setHasAdded(false);
  _setHasAddedFinal(false);
  _displayedBalls.clear();
  _setShowActionIcons(false);
  _setNumbers(List.filled(5, 0));
  _setShowFinalButtons(false);
  _setHasPlayedOnce(false);

  return ReserveOutcome(
    ok: false,
    code: 'CONFLICT',
    message: 'Algunos números ya no están disponibles. Vuelve a jugar.',
    status: status,
  );

} else if (code == 'LIMIT_REACHED' || code == 'PARTIAL_EXISTS') {
  // El backend indica que ya tienes reserva en este juego (completa o parcial)
  final data = (res['data'] as Map<String, dynamic>? ?? {});
  final gid = (data['game_id'] as num?)?.toInt();
  final nums = ((data['numbers'] as List?) ?? const [])
      .map((e) => int.parse(e.toString()))
      .toList();

  if (gid != null && nums.isNotEmpty) {
    _gameId = gid;
    _lastReservedGameId = gid;
    _lastReservedNumbers = List<int>.from(nums);

    _setNumbers(List<int>.from(nums));
    _displayedBalls
      ..clear()
      ..addAll(nums);

    // Muestra como “selección existente”
    _setHasAdded(true);
    _setShowActionIcons(true);
    _setShowFinalButtons(true);
    _setHasPlayedOnce(true);

    // Si eran 5, marcamos como final para que UI oculte JUGAR/RESERVAR
    if (nums.length >= 5) {
      _setHasAddedFinal(true);
    }
  }

  return ReserveOutcome(
    ok: false,
    code: code,
    message: msg.isNotEmpty
        ? msg
        : (code == 'LIMIT_REACHED'
            ? 'Ya tienes 5 números reservados para este juego.'
            : 'Tienes una reserva parcial en este juego. Libérala antes de reemplazar.'),
    status: status,
  );

} else if (code == 'NETWORK_ERROR') {
  return const ReserveOutcome(
    ok: false,
    code: 'NETWORK_ERROR',
    message: 'No hay conexión con el servidor.',
  );

} else if (status == 401 || status == 403) {
  await initSession(); // re-lee token por si cambió
  return ReserveOutcome(
    ok: false,
    code: 'UNAUTHORIZED',
    message: 'No autorizado con la sesión actual.',
    status: status,
  );

} else {
  return ReserveOutcome(
    ok: false,
    code: code.isEmpty ? null : code,
    message: msg,
    status: status,
  );
}
  }
  Future<ReserveOutcome?> _releasePreviousIfNeeded() async {
    _releasedPrevious = false; // reset por si venimos de otro ciclo

    if (_lastReservedGameId == null) return null;

    final res = await _gamesApi.release(
      gameId: _lastReservedGameId!,
      token: _authToken, // ✅ Authorization requerido por backend
      xUserId: null, // ❌ no mezclar override
    );

    final status = res['status'] as int?;
    final code = (res['code'] ?? '').toString();

    if (res['ok'] == true) {
      _releasedPrevious = true; // 👈 hubo borrado real en DB
      _lastReservedGameId = null;
      return null;
    }
    if (status == 404 || code == 'NOT_FOUND') {
      _releasedPrevious = false; // 👈 no había nada que borrar
      _lastReservedGameId = null;
      return null;
    }

    final msg = (res['message'] ?? 'No se pudo liberar la reserva anterior.')
        .toString();
    return ReserveOutcome(
      ok: false,
      code: code.isEmpty ? 'RELEASE_ERROR' : code,
      message: msg,
      status: status,
    );
  }

  // ======= Utilidades de edición local =======
  void clearSelection() {
    _setHasAdded(false);
    _displayedBalls.clear();
    _setShowActionIcons(false);
    notifyListeners();
  }

  // Deja la UI en estado inicial (como recién abierta): sin selección y con botón JUGAR visible.
  void resetToInitial() {
    _setReserving(false);
    _displayedBalls.clear();
    _setNumbers(List.filled(5, 0));
    _setShowFinalButtons(false);
    _setHasAddedFinal(false);
    _setHasAdded(false);
    _setShowActionIcons(false);
    _setCurrentBigBall(null);
    _setHasPlayedOnce(false);

    // 👇 IMPORTANTE: “despegar” del juego viejo
    _gameId = null;
    _generated = const [];
    _lastReservedGameId = null;
    _lastReservedNumbers = null;

    notifyListeners();
  }

  // Permite a la Vista setear números manuales si hicieras un editor
  void setNumbersDirect(List<int> fiveNumbers) {
    if (fiveNumbers.length != 5) return;
    final maxValue = pow(10, _digitsPerBall).toInt() - 1;
    if (!fiveNumbers.every((n) => n >= 0 && n <= maxValue)) return;

    _setNumbers(List<int>.from(fiveNumbers));
  }

  // ======= NOTIFICACIONES =======
  Future<List<Map<String, dynamic>>> checkNotifications() async {
    if (_authToken == null || _authToken!.isEmpty) return [];

    final res = await _gamesApi.getNotifications(token: _authToken);

    if (res['ok'] != true) return [];

    final data = res['data'] as List<dynamic>? ?? [];
    return data.map((e) => e as Map<String, dynamic>).toList();
  }

  // ======= Estado =======
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;

  List<Map<String, dynamic>> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Map<String, dynamic> _normalizeNotification(Map raw) {
    final m = raw.cast<String, dynamic>();

    // Algunas APIs devuelven todo en "data"
    final data = (m['data'] is Map)
        ? (m['data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    // id puede venir como id, nid, notification_id
    final id = _toInt(
      m['id'] ?? m['nid'] ?? m['notification_id'] ?? data['id'],
    );

    // kind puede venir en data.type, type o kind
    final kind = (data['type'] ?? m['type'] ?? m['kind'] ?? '').toString();

    // título/cuerpo
    final title = (m['title'] ?? data['title'] ?? '').toString();
    final body = (m['body'] ?? data['body'] ?? m['message'] ?? '').toString();

    // leído
    final read =
        (m['read'] == true) || (m['is_read'] == true) || (data['read'] == true);

    // fecha
    final createdAt = (m['created_at'] ?? data['created_at'] ?? m['date'] ?? '')
        .toString();

    // payload adicional común (mapea claves típicas de rechazos)
    final payload = <String, dynamic>{
      ...((m['payload'] is Map)
          ? (m['payload'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{}),
      ...data,
    };

    return {
      'id': id ?? -1, // evita nulls
      'kind': kind,
      'title': title,
      'body': body,
      'read': read,
      'created_at': createdAt,
      'payload': payload,
    };
  }

  // ======= Cargar notificaciones =======
  Future<void> loadNotifications() async {
    if (_authToken == null || _authToken!.isEmpty) return;

    final res = await _gamesApi.getNotifications(
      token: _authToken,
      unreadOnly: false,
      page: 1,
      perPage: 100,
    );

    if (res['ok'] != true) return;

    final data = res['data'];

    // Acepta { items: [...] } o una lista directa
    final List rawList = (data is Map<String, dynamic>)
        ? (data['items'] as List? ?? const [])
        : (data as List? ?? const []);

    // Normaliza todos los items
    _notifications = rawList
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => _normalizeNotification(e))
        .toList();

    // Recalcula badge
    _unreadCount = _notifications.where((n) => n['read'] == false).length;

    notifyListeners();
  }

  Future<void> loadHistory({int page = 1, int perPage = 50}) async {
    if (_authToken == null || _authToken!.isEmpty) return;

    final res = await _gamesApi.getHistory(
      token: _authToken,
      page: page,
      perPage: perPage,
    );

    if (res['ok'] == true) {
      _history = ((res['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> fetchWinnerNotificationsOnce() async {
    if (_authToken == null || _authToken!.isEmpty) {
      return [];
    }

    final res = await _gamesApi.getNotifications(
      token: _authToken,
      xUserId: _authToken == null ? _devUserId : null,
      unreadOnly: true,
      page: 1,
      perPage: 100,
    );
    if (res['ok'] != true) return [];

    final items = (res['data'] as List).cast<Map<String, dynamic>>();

    int prio(String? t) => switch (t) {
      'you_won' => 3,
      'winner_congrats' => 2,
      'winner_announced' => 1,
      _ => 0,
    };

    final bestByGame = <int, Map<String, dynamic>>{};
    for (final n in items) {
      final id = int.tryParse('${n['id'] ?? n['nid'] ?? n['notification_id']}');
      if (id == null || _shownNotifIds.contains(id)) continue;

      final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final kind = data['type']?.toString();
      const allowed = {'winner_announced', 'winner_congrats', 'you_won'};
      if (!allowed.contains(kind)) {
        continue;
      }

      final gameId = (data['game_id'] as num?)?.toInt();
      if (gameId == null) continue;

      final cand = {
        'id': id,
        'kind': kind,
        'game_id': gameId,
        'winning_number': data['winning_number'],
        'message': n['body'] ?? n['message'] ?? '',
        'created_at': n['created_at'] ?? '',
      };

      final prev = bestByGame[gameId];
      if (prev == null ||
          prio(kind) > prio(prev['kind'] as String?) ||
          (prio(kind) == prio(prev['kind'] as String?) &&
              (cand['id'] as int) > (prev['id'] as int))) {
        bestByGame[gameId] = cand;
      }
    }

    final result = bestByGame.values.toList()
      ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

    // 👇 evita re-mostrar en esta sesión y márcalas como leídas en el backend
    final ids = result.map<int>((m) => m['id'] as int).toList();
    _shownNotifIds.addAll(ids);
    unawaited(markReadIds(ids));

    return result;
  }

  Future<Map<String, String>?> peekScheduleOnce() async {
    if (_authToken == null || _authToken!.isEmpty) return null;

    final api = await _gamesApi.peekSchedule(token: _authToken, xUserId: null);
    if (api['ok'] != true) return null;

    final item = api['data'];
    if (item == null || item is! Map) return null;
    final m = Map<String, dynamic>.from(item);

    final int? nid = (m['id'] as num?)?.toInt();
    if (nid == null) return null;
    if (_shownNotifIds.contains(nid)) return null;
    _shownNotifIds.add(nid);
    unawaited(markReadIds([nid]));

    final String title = (m['title'] ?? '¡Juego programado!').toString();
    final String bodyFromApi = (m['body'] ?? '').toString();

    final Map<String, dynamic> data = (m['data'] is Map)
        ? Map<String, dynamic>.from(m['data'])
        : <String, dynamic>{};

    final lottery = (data['lottery'] ?? '').toString();
    final date = (data['date'] ?? '').toString();
    final time = (data['time'] ?? '').toString();
    final gameId = (data['game_id'] ?? '').toString();

    final String body = bodyFromApi.isNotEmpty
        ? bodyFromApi
        : 'El administrador ha indicado que se jugará con la lotería $lottery el $date a las $time.';

    return {
      'id': '$nid',
      'title': title,
      'body': body,
      'lottery': lottery,
      'date': date,
      'time': time,
      'game_id': gameId,
    };
  }

  Future<void> markUnreadAsRead() async {
    if (_authToken == null || _authToken!.isEmpty) return;
    // Asegúrate de que _notifications tenga {id, read}
    final ids = _notifications
        .where((n) => n['read'] == false || n['read'] == null)
        .map<int>((n) => _toInt(n['id']) ?? -1)
        .where((id) => id > 0)
        .toList();

    if (ids.isEmpty) return;

    final res = await _gamesApi.markNotificationsRead(
      ids: ids,
      token: _authToken,
      xUserId: null,
    );
    // Optimista: marca localmente
    if (res['ok'] == true) {
      for (final n in _notifications) {
        if (ids.contains((n['id'] as num).toInt())) {
          n['read'] = true;
        }
      }
      _unreadCount = 0;
      notifyListeners();
    }
  }

  // Marca como leídas las notificaciones con esos IDs en el backend
  Future<void> markReadIds(List<int> ids) async {
    if (ids.isEmpty) return;
    if (_authToken == null || _authToken!.isEmpty) return;

    try {
      await _gamesApi.markNotificationsRead(
        ids: ids,
        token: _authToken,
        // xUserId: _authToken == null ? _devUserId : null,  // normalmente no hace falta
      );

      // Actualiza cache local (opcional pero útil para el badge)
      _notifications = _notifications.map((n) {
        final nid = (n['id'] as num?)?.toInt();
        if (nid != null && ids.contains(nid)) {
          return {...n, 'read': true};
        }
        return n;
      }).toList();
      _unreadCount = _notifications.where((n) => n['read'] == false).length;
      notifyListeners();
    } catch (_) {
      // Ignora silenciosamente fallos de red aquí si prefieres
    }
  }

  /// Devuelve 1 sola alerta de programación a partir del listado normal
  /// (busca la más reciente con type == 'schedule_set' y que no se haya mostrado).
  Future<Map<String, String>?> fetchScheduleFromListOnce() async {
    if (_authToken == null || _authToken!.isEmpty) return null;

    // Trae NO LEÍDAS primero
    final res = await _gamesApi.getNotifications(
      token: _authToken,
      unreadOnly: true,
      page: 1,
      perPage: 100,
    );
    if (res['ok'] != true) return null;

    final items = (res['data'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic>? best;

    for (final n in items) {
      final id = (n['id'] as num?)?.toInt();
      if (id == null || _shownNotifIds.contains(id)) continue;

      final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final kind = (data['type'] ?? n['type']).toString();

      if (kind == 'schedule_set' || kind == 'game_scheduled') {
        best = n;
        break; // tomamos la primera no leída (ya viene ordenada del backend)
      }
    }

    if (best == null) return null;

    final id = (best['id'] as num).toInt();
    _shownNotifIds.add(id);
    unawaited(markReadIds([id]));

    final data = (best['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final lottery = (data['lottery'] ?? '').toString();
    final date = (data['date'] ?? '').toString();
    final time = (data['time'] ?? '').toString();
    final gameId = (data['game_id'] ?? '').toString();

    final title = (best['title'] ?? '¡Juego programado!').toString();
    final body =
        (best['body'] ??
                'El administrador ha indicado que se jugará con la lotería $lottery el $date a las $time.')
            .toString();

    return {
      'id': '$id',
      'title': title,
      'body': body,
      'lottery': lottery,
      'date': date,
      'time': time,
      'game_id': gameId,
    };
  }

  Future<void> applyPremiumFromStore(bool premium) async {
    _isPremium = premium;

    // Persiste también en sesión, para que al reabrir la app no se pierda
    await _session.setIsPremium(premium);

    // Opcional: si estabas en algún estado intermedio, limpia para evitar “parpadeo”
    if (premium) {
      resetToInitial(); // limpia animaciones/flags que pudieran quedar a medias
    }

    notifyListeners();
  }
}
