import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:base_app/presentation/screens/dashboard/logic/sound_helper.dart';
import 'package:base_app/data/api/games_api.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/domain/auth/auth_repository.dart';
import 'dart:math';
import 'package:base_app/presentation/screens/dashboard/logic/game_mode.dart';

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
  // Alias genéricos de la última reserva (modo actual)
  int? _lastReservedGameId;
  List<int>? _lastReservedNumbers;
  bool _releasedPrevious = false;

  // ======= Reservas por tipo de juego =======
  int? _lastReservedGameId2;
  List<int>? _lastReservedNumbers2;
  bool _releasedPrevious2 = false;

  int? _lastReservedGameId3;
  List<int>? _lastReservedNumbers3;
  bool _releasedPrevious3 = false;

  int? _lastReservedGameId4;
  List<int>? _lastReservedNumbers4;
  bool _releasedPrevious4 = false;

int? _lastReservedGameId5;       // quinta
List<int>? _lastReservedNumbers5; // quinta
bool _releasedPrevious5 = false;

void _setCurrentLastReservedGameId(int? v) {
  if (_mode == GameMode.digits2) _lastReservedGameId2 = v;
  else if (_mode == GameMode.digits3) _lastReservedGameId3 = v;
  else if (_mode == GameMode.digits4) _lastReservedGameId4 = v;
  else if (_mode == GameMode.quinta) _lastReservedGameId5 = v;
}

void _setCurrentLastReservedNumbers(List<int>? v) {
  if (_mode == GameMode.digits2) _lastReservedNumbers2 = v;
  else if (_mode == GameMode.digits3) _lastReservedNumbers3 = v;
  else if (_mode == GameMode.digits4) _lastReservedNumbers4 = v;
  else if (_mode == GameMode.quinta) _lastReservedNumbers5 = v;
}

void _setCurrentReleasedPrevious(bool v) {
  if (_mode == GameMode.digits2) _releasedPrevious2 = v;
  else if (_mode == GameMode.digits3) _releasedPrevious3 = v;
  else if (_mode == GameMode.digits4) _releasedPrevious4 = v;
  else if (_mode == GameMode.quinta) _releasedPrevious5 = v;
}

  int? _lastClosedGameId; // id del último juego que quedó cerrado
  int? get lastClosedGameId => _lastClosedGameId;
  int? _userId;
  int? get userId => _userId;
  bool _isPremium = false;
  bool get isPremium => _isPremium;
// ✅ Máximo de dígitos permitidos por plan (3/4/5)
int _maxDigitsAllowed = 3;
int get maxDigitsAllowed => _maxDigitsAllowed;

bool get canPlay2 => true; // siempre gratis
bool get canPlay3 => true;
bool get canPlay4 => _maxDigitsAllowed >= 4;
bool get canPlay5 => _maxDigitsAllowed >= 5;

  // ======= Configuración del juego (ESCALABLE) =======
  GameMode _mode = GameMode.digits2; // por defecto: 2 cifras (gratis)

  // Cache por modo (escala a 5ta, etc.)
  final Map<GameMode, int?> _gameIdByMode = {
    GameMode.digits2: null,
    GameMode.digits3: null,
    GameMode.digits4: null,
    GameMode.quinta: null,
  };

final Map<GameMode, List<int>> _numbersByMode = {
  GameMode.digits2: List.filled(5, 0),
  GameMode.digits3: List.filled(5, 0),
  GameMode.digits4: List.filled(5, 0),
  GameMode.quinta: List.filled(5, 0),
};


  int get digitsPerBall => (_mode == GameMode.quinta) ? 5 : _mode.baseDigits;


  GameMode get mode => _mode;


void setGameMode(GameMode value) {
  if (_mode == value) return;

  _mode = value;

  // 🔹 1) Limpiar todo lo visual / de reserva del modo anterior
  _setReserving(false);
  _displayedBalls.clear();
  _setShowActionIcons(false);
  _setHasAdded(false);
  _setHasAddedFinal(false);
  _setShowFinalButtons(false);
  _setCurrentBigBall(null);
  _setHasPlayedOnce(false);

  // 🔹 2) Cargar cache del modo correspondiente
  _gameId = _gameIdByMode[_mode];

  final cachedNums = _numbersByMode[_mode] ?? List.filled(5, 0);
  _setNumbers(List<int>.from(cachedNums));

  // 🔹 3) Si ya había selección real, mostrarla
  if (_gameId != null && cachedNums.any((n) => n != 0)) {
    _displayedBalls.addAll(cachedNums);
    _setHasAdded(true);
    _setHasAddedFinal(true);
    _setShowActionIcons(true);
    _setShowFinalButtons(true);
    _setHasPlayedOnce(true);
  }
}

void setDigitsPerBall(int value) {
  if (value == 2) return setGameMode(GameMode.digits2);
  if (value == 3) return setGameMode(GameMode.digits3);

  if (value == 4) {
    if (!canPlay4) return;
    return setGameMode(GameMode.digits4);
  }

  if (value == 5) {
    if (!canPlay5) return;
    return setGameMode(GameMode.quinta);
  }
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

String _fmtNums(List<int> xs) {
  String fmtOne(int n) {
    final s = n.toString().padLeft(digitsPerBall, '0');

    // Quinta: 5 dígitos visuales como 1234-5 (solo UI)
    if (_mode == GameMode.quinta) {
      return '${s.substring(0, 4)}-${s.substring(4)}';
    }

    // 3 o 4 dígitos normal
    return s;
  }

  return xs.map(fmtOne).join(' · ');
}



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
  _numbers = List<int>.from(list); // ✅ copia defensiva
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

  // 🔴 Sin token: limpiar todo y dejar tablero vacío
  if (token == null || token.isEmpty) {
    _authToken = null;
    _userId = null;
    _isPremium = false;
    _history = [];
    _lastReservedGameId = null;
    _lastReservedNumbers = null;
    _lastClosedGameId = null;
    _shownNotifIds.clear();

    // 👇 limpiar caches por tipo de juego
    _gameIdByMode[GameMode.digits2] = null;
    _numbersByMode[GameMode.digits2] = List.filled(5, 0);

    _gameIdByMode[GameMode.digits3] = null;
    _numbersByMode[GameMode.digits3] = List.filled(5, 0);

    _gameIdByMode[GameMode.digits4] = null;
    _numbersByMode[GameMode.digits4] = List.filled(5, 0);

    _gameIdByMode[GameMode.quinta] = null;
    _numbersByMode[GameMode.quinta] = List.filled(5, 0);

    _lastReservedGameId2 = null;
    _lastReservedNumbers2 = null;
    _lastReservedGameId3 = null;
    _lastReservedNumbers3 = null;
    _lastReservedGameId4 = null;
    _lastReservedNumbers4 = null;

    resetToInitial();
    _setSessionReady(false);
    notifyListeners();
    return;
  }


  // ✅ Hay sesión
  _authToken = token;

  final dynamic uid = await _session.getUserId();
  if (uid is int) {
    _userId = uid;
  } else if (uid is String) {
    _userId = int.tryParse(uid);
  } else {
    _userId = null;
  }

  // PRO guardado en sesión (tu backend lo marca cuando valida la compra)
  final fromSession = await _session.getIsPremium() == true;
  _isPremium = fromSession;
final storedMax = await _session.getMaxDigitsAllowed();
_maxDigitsAllowed = storedMax ?? (_isPremium ? 4 : 3); 
// 👆 fallback: si es premium pero no sabemos cuál, asumimos 4 (cm)

  _setSessionReady(true);
  notifyListeners();

  // 👇 IMPORTANTE:
  // 1) Traer historial para saber qué juegos están cerrados
  // 2) Restaurar la selección SOLO si el juego sigue abierto
  await loadHistory();
  await restoreSelectionIfAny();
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
    final modeSnapshot = _mode;
  final digitsSnapshot = (modeSnapshot == GameMode.quinta) ? 5 : modeSnapshot.baseDigits;
  // requiere sesión válida
  if (_authToken == null || _authToken!.isEmpty) return;

  final res = await _gamesApi.getMySelection(
    token: _authToken,
    digits: digitsSnapshot,

  );

  if (res['ok'] != true) {
    // No hay selección para este tipo de juego → deja todo en estado inicial
    resetToInitial();
    return;
  }

  final data = (res['data'] as Map<String, dynamic>? ?? {});
  final gid = (data['game_id'] as num?)?.toInt();
  final numsDyn = (data['numbers'] as List?) ?? const [];
  final nums = numsDyn.map((e) => int.parse(e.toString())).toList();

  if (gid == null || nums.length != 5) {
    // Datos incompletos → tratar como "sin selección" para este tipo
    resetToInitial();
    return;
  }

  // ⛔ No restaurar si ese juego ya cerró (según el historial ya cargado)
  final closed = _history.any((m) {
    final mid = (m['game_id'] as num?)?.toInt();
    if (mid != gid) return false;
    final status =
        (m['status'] ?? m['result'] ?? '').toString().toLowerCase();
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

    // 👇 Juego cerrado y sin selección vigente → 000
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
  // Guardar la reserva por tipo de juego (cache + variables mode-específicas)
  _gameIdByMode[modeSnapshot] = gid;
  _numbersByMode[modeSnapshot] = List<int>.from(nums);
  if (modeSnapshot == GameMode.digits2) {
    _lastReservedGameId2 = gid;
    _lastReservedNumbers2 = List<int>.from(nums);
  } else if (modeSnapshot == GameMode.digits3) {
    _lastReservedGameId3 = gid;
    _lastReservedNumbers3 = List<int>.from(nums);
  } else if (modeSnapshot == GameMode.digits4) {
    _lastReservedGameId4 = gid;
    _lastReservedNumbers4 = List<int>.from(nums);
  } else if (modeSnapshot == GameMode.quinta) {
    _lastReservedGameId5 = gid;
    _lastReservedNumbers5 = List<int>.from(nums);
  }


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
    // limpiar también reservas por modo
    _gameIdByMode[GameMode.digits2] = null;
    _numbersByMode[GameMode.digits2] = List.filled(5, 0);

    _gameIdByMode[GameMode.digits3] = null;
    _numbersByMode[GameMode.digits3] = List.filled(5, 0);

    _gameIdByMode[GameMode.digits4] = null;
    _numbersByMode[GameMode.digits4] = List.filled(5, 0);

    _gameIdByMode[GameMode.quinta] = null;
    _numbersByMode[GameMode.quinta] = List.filled(5, 0);

    _lastReservedGameId2 = null;
    _lastReservedNumbers2 = null;
    _lastReservedGameId3 = null;
    _lastReservedNumbers3 = null;
    _lastReservedGameId4 = null;
    _lastReservedNumbers4 = null;

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
  int? avoidGameId,
  int attempts = 3,
  bool ignoreExistingSelection = false, // 👈 NUEVO
}) async {
  if (_animating || _saving || _reserving) return GenerateState.error;

  final String? tokenToUse =
      (_authToken != null && !_isJwtExpired(_authToken!))
          ? _authToken
          : null;
  final int? xUserIdToUse = (tokenToUse == null) ? _devUserId : null;

  // -------------------------
  // 1. SI YA HABÍA SELECCIÓN (solo si NO venimos de retry)
  // -------------------------
  if (!ignoreExistingSelection && tokenToUse != null) {
    try {
      final pre = await _gamesApi.getMySelection(
        token: tokenToUse,
        digits: digitsPerBall,
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

_gameIdByMode[_mode] = gid;
_numbersByMode[_mode] = List<int>.from(nums);




          return GenerateState.ok;
        }
      }
    } catch (_) {
      // ignora errores de red
    }
  }

  // -------------------------
  // 2. PREPARAR ESTADO LÓGICO
  // -------------------------
  _setHasPlayedOnce(true);

  Map<String, dynamic>? data;

  // -------------------------
  // 3. PEDIR NÚMEROS AL BACKEND
  // -------------------------
for (var i = 0; i < attempts; i++) {
  final res = await _gamesApi.generate(
    token: tokenToUse,
    xUserId: xUserIdToUse,
    digits: digitsPerBall,
  );

  if (res['ok'] == true) {
    final d = (res['data'] as Map<String, dynamic>? ?? {});
    final gidDynamic = d['game_id'];
    final int? gid = (gidDynamic is num) ? gidDynamic.toInt() : null;

    debugPrint('[generate] OK digits=$digitsPerBall gameId=$gid');

    // 👇 Solo saltamos si ESPECÍFICAMENTE queremos evitar un game_id concreto
    if (avoidGameId != null && gid != null && gid == avoidGameId) {
      debugPrint(
        '[generate] evitando gameId=$gid porque coincide con avoidGameId=$avoidGameId',
      );
      // probamos otra vez
      await Future.delayed(const Duration(milliseconds: 200));
      continue;
    }

    // ✅ Aceptamos la respuesta AUNQUE game_id sea null (NO_GAME)
    data = d;
    break;
  } else {
    debugPrint(
      '[generate] ERROR digits=$digitsPerBall '
      'status=${res['status']} code=${res['code']} msg=${res['message']}',
    );
    return GenerateState.error;
  }

  await Future.delayed(const Duration(milliseconds: 200));
}

  if (data == null) {
    debugPrint(
      'generateAnimatedNumbers: data null tras $attempts intentos (digits=$digitsPerBall)',
    );
    return GenerateState.error;
  }

  // -------------------------
  // 4. YA TENGO LOS NÚMEROS → ANIMO
  // -------------------------
  try {
    final gidDynamic2 = data['game_id'];
_gameId = (gidDynamic2 is num) ? gidDynamic2.toInt() : null;

    final List<dynamic> nums = data['numbers'] as List<dynamic>;
    _generated = nums.map((e) => int.parse(e.toString())).toList();
debugPrint('[generate] numbers=$_generated digits=$digitsPerBall mode=$_mode');

    // Pasamos los 5 DEFINITIVOS a la UI
    _setNumbers(List<int>.from(_generated));

    // cache por tipo de juego
_gameIdByMode[_mode] = _gameId;
_numbersByMode[_mode] = List<int>.from(_generated);


    // Ocultamos botones mientras anima
    _setShowFinalButtons(false);

    _setAnimating(true);

    // Duración total: última balota 1 + (n-1) segundos
    final lastDurationSeconds = 1 + (_generated.length - 1);
    await Future.delayed(Duration(seconds: lastDurationSeconds));
    await Future.delayed(const Duration(milliseconds: 300));

    _setAnimating(false);
    _setShowFinalButtons(true);
    return GenerateState.ok;
  } catch (e, st) {
    debugPrint('generateAnimatedNumbers exception: $e\n$st');
    _setAnimating(false);
    return GenerateState.error;
  }
}


Future<GenerateState> openFreshGame({int attempts = 3}) async {
  // El backend ya no devuelve juegos cerrados,
  // solo pedimos un juego nuevo respetando selección previa (si existe).
  return generateAnimatedNumbers(
    avoidGameId: null,
    attempts: attempts,
    ignoreExistingSelection: false,
  );
}


Future<void> retry() async {

debugPrint('[RETRY] mode=$_mode digitsPerBall=$digitsPerBall');

  // Log para ver si realmente entra
  debugPrint(
    '[RETRY] tap digits=$digitsPerBall '
    'anim=$_animating saving=$_saving reserving=$_reserving',
  );

  // Evita taps dobles mientras está ocupada
  if (_animating || _saving || _reserving) {
    debugPrint('[RETRY] abortado: aún ocupado.');
    return;
  }

  // Cancelar cualquier animación de reserva/overlay
  _setReserving(false);
  _displayedBalls.clear();
  _setShowActionIcons(false);
  _setCurrentBigBall(null);

  // 👉 Guardamos el estado actual por si algo sale mal
  final prevNumbers = List<int>.from(_numbers);
  final prevShowFinalButtons = _showFinalButtons;
  final prevHasAdded = _hasAdded;
  final prevHasAddedFinal = _hasAddedFinal;

  // NO tocamos _showFinalButtons ni _hasAdded / _hasAddedFinal todavía

  final result = await generateAnimatedNumbers(
    ignoreExistingSelection: true,
  );

  debugPrint('[RETRY] result=$result digits=$digitsPerBall');

  // Si el backend falla, hacemos fallback a preview local
  if (result == GenerateState.error) {
    debugPrint(
      '[RETRY] generateAnimatedNumbers ERROR → usando preview local.',
    );

    // Restauramos el estado previo ANTES del preview
    _setNumbers(prevNumbers);
    _setShowFinalButtons(prevShowFinalButtons);
    _setHasAdded(prevHasAdded);
    _setHasAddedFinal(prevHasAddedFinal);

    // 👇 Animación local solo visual (no cambia _gameId)
    final previewResult = await generateLocalPreview();
    debugPrint('[RETRY] preview local result=$previewResult');
    return;
  }

  // Si fue OK, ahora sí dejamos listo para el nuevo ciclo
  _setHasAdded(false);
  _setHasAddedFinal(false);
}



Future<GenerateState> generateLocalPreview() async {
  
  if (_animating || _saving || _reserving) return GenerateState.error;

  _gameId = null;
  _setShowFinalButtons(false);
  _setHasPlayedOnce(true);

  final rnd = Random();

  // ✅ dígitos reales por modo (quinta=5)
  final int digits = (_mode == GameMode.quinta) ? 5 : _mode.baseDigits;
  final int maxValue = pow(10, digits).toInt();

  debugPrint('[PREVIEW] mode=$_mode digits=$digits maxValue=$maxValue');

  final used = <int>{};
  while (used.length < 5) {
    used.add(rnd.nextInt(maxValue));
  }
  _generated = used.toList();
debugPrint('[PREVIEW] generated=$_generated');
  _setNumbers(List<int>.from(_generated));
  _setAnimating(true);

  final lastDurationSeconds = 1 + (_generated.length - 1);
  await Future.delayed(Duration(seconds: lastDurationSeconds));
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

  // 2 cifras es gratis: no requiere premium ni upgrade
  if (!_mode.isFreeMode) {
    if (!_isPremium) {
      return const ReserveOutcome(
        ok: false,
        code: 'NEED_PREMIUM',
        message: 'Necesitas PRO para reservar.',
        status: 403,
      );
    }
    if (digitsPerBall > _maxDigitsAllowed) {
      return const ReserveOutcome(
        ok: false,
        code: 'NEED_UPGRADE',
        message: 'Tu plan no permite este modo. Actualiza tu suscripción.',
        status: 403,
      );
    }
  }

  final stillRevealing = _animating || !_showFinalButtons;
  if (stillRevealing) {
    return const ReserveOutcome(
      ok: false,
      code: 'INVALID_STATE',
      message: 'Aún no hay selección lista.',
    );
  }

final bool isValid = (() {
if (_mode == GameMode.quinta) {
  if (_numbers.length != 5) return false;
  return _numbers.every((n) => n >= 0 && n <= 99999);
}


  final maxValue = pow(10, digitsPerBall).toInt() - 1;
  return _numbers.length == 5 && _numbers.every((n) => n >= 0 && n <= maxValue);
})();


  if (!isValid) {
    return const ReserveOutcome(
      ok: false,
      code: 'OUT_OF_RANGE',
      message: 'Selección fuera de rango.',
    );
  }

final List<int>? prevRaw = (_mode == GameMode.digits2)
    ? _lastReservedNumbers2
    : (_mode == GameMode.digits3)
        ? _lastReservedNumbers3
        : (_mode == GameMode.digits4)
            ? _lastReservedNumbers4
            : (_mode == GameMode.quinta)
                ? _lastReservedNumbers5
                : null;

  final prevNumbers = (prevRaw == null) ? null : List<int>.from(prevRaw);


  // Liberar reserva previa
  final releaseOutcome = await _releasePreviousIfNeeded();
  if (releaseOutcome != null && !releaseOutcome.ok) {
    return releaseOutcome;
  }

  // Animación de reserva
  _setReserving(true);
  _displayedBalls.clear();
  _setShowActionIcons(false);
  _setHasAdded(true);

  for (final number in _numbers) {
    _setCurrentBigBall(number);
    await SoundHelper.playPopSound();
    await Future.delayed(const Duration(seconds: 1));
    _setCurrentBigBall(null);
    _displayedBalls.add(number);
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 300));
  }

  _setShowActionIcons(true);

  if (_isJwtExpired(_authToken!)) {
    _setReserving(false);
    return const ReserveOutcome(
      ok: false,
      code: 'TOKEN_EXPIRED',
      message: 'Tu sesión venció.',
    );
  }

  // ============================
  // ⚠️ COMMIT SIN BLOQUEO (NO_GAME)
  // ============================
  _setSaving(true);

  final res = await _gamesApi.commit(
    gameId: _gameId,          // 👈 se permite null
    numbers: _numbers,
    token: _authToken,
    xUserId: null,
    digits: digitsPerBall,   // 👈 importante
  );

  _setSaving(false);
  _setReserving(false);

  // -------------------- OK --------------------
  if (res['ok'] == true) {
    final data = (res['data'] as Map<String, dynamic>? ?? {});
    _setHasAddedFinal(true);

    _lastReservedGameId = _gameId;
    _lastReservedNumbers = List<int>.from(_numbers);
    // 👇 guardar reserva por modo
if (_mode == GameMode.digits2) {
  _lastReservedGameId2 = _gameId;
  _lastReservedNumbers2 = List<int>.from(_numbers);
} else if (_mode == GameMode.digits3) {
  _lastReservedGameId3 = _gameId;
  _lastReservedNumbers3 = List<int>.from(_numbers);
} else if (_mode == GameMode.digits4) {
  _lastReservedGameId4 = _gameId;
  _lastReservedNumbers4 = List<int>.from(_numbers);
} else if (_mode == GameMode.quinta) {
  _lastReservedGameId5 = _gameId;
  _lastReservedNumbers5 = List<int>.from(_numbers);
}



    final userIdUsed = (data['user_id_used'] as num?)?.toInt();
    _lastReservedUserId = userIdUsed ?? _lastReservedUserId;

    final completed =
        data['game_completed'] == true || res['game_completed'] == true;

    final gid = _gameId;
    await loadHistory();
    final closedNow = (gid != null) && _isGameClosedLocal(gid);

    final finalCompleted = completed || closedNow;
    if (finalCompleted) {
      _lastClosedGameId = gid;

      if (_mode == GameMode.digits2) {
        _lastReservedGameId2 = null;
        _lastReservedNumbers2 = null;
      } else if (_mode == GameMode.digits3) {
        _lastReservedGameId3 = null;
        _lastReservedNumbers3 = null;
      } else if (_mode == GameMode.digits4) {
        _lastReservedGameId4 = null;
        _lastReservedNumbers4 = null;
      } else if (_mode == GameMode.quinta) {
        _lastReservedGameId5 = null;
        _lastReservedNumbers5 = null;
      }

      _gameId = null;
      _lastReservedGameId = null;
      _lastReservedNumbers = null;
    } else {
      _lastClosedGameId = null;
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

    return ReserveOutcome(
      ok: true,
      gameCompleted: finalCompleted,
    );
  }

  // -------------------- ERRORES --------------------
  final code = (res['code'] ?? '').toString();
  final msg = (res['message'] ?? 'No se pudo guardar la selección.').toString();
  final status = res['status'] as int?;

  if (code == 'GAME_SWITCHED') {
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
  }

  if (code == 'CONFLICT' || status == 409) {
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
  }

  if (code == 'LIMIT_REACHED' || code == 'PARTIAL_EXISTS') {
    final data = (res['data'] as Map<String, dynamic>? ?? {});
    final gid = (data['game_id'] as num?)?.toInt();
    final nums = ((data['numbers'] as List?) ?? const [])
        .map((e) => int.parse(e.toString()))
        .toList();

    if (gid != null && nums.isNotEmpty) {
      _gameId = gid;
      _lastReservedGameId = gid;
      _lastReservedNumbers = List<int>.from(nums);
      // guardar esa reserva parcial por modo
      if (digitsPerBall == 2) {
        _lastReservedGameId2 = gid;
        _lastReservedNumbers2 = List<int>.from(nums);
      } else if (digitsPerBall == 3) {
        _lastReservedGameId3 = gid;
        _lastReservedNumbers3 = List<int>.from(nums);
      } else if (digitsPerBall == 4) {
        _lastReservedGameId4 = gid;
        _lastReservedNumbers4 = List<int>.from(nums);
      } else {
        _lastReservedGameId5 = gid;
        _lastReservedNumbers5 = List<int>.from(nums);
      }

      _setNumbers(List<int>.from(nums));
      _displayedBalls
        ..clear()
        ..addAll(nums);

      _setHasAdded(true);
      _setShowActionIcons(true);
      _setShowFinalButtons(true);
      _setHasPlayedOnce(true);

      if (nums.length >= 5) {
        _setHasAddedFinal(true);
      }
    }

    return ReserveOutcome(
      ok: false,
      code: code,
      message: msg,
      status: status,
    );
  }

  if (code == 'NETWORK_ERROR') {
    return const ReserveOutcome(
      ok: false,
      code: 'NETWORK_ERROR',
      message: 'No hay conexión con el servidor.',
    );
  }

  if (status == 401 || status == 403) {
    await initSession();
    return ReserveOutcome(
      ok: false,
      code: 'UNAUTHORIZED',
      message: 'No autorizado con la sesión actual.',
      status: status,
    );
  }

  return ReserveOutcome(
    ok: false,
    code: code.isEmpty ? null : code,
    message: msg,
    status: status,
  );
}
Future<ReserveOutcome?> _releasePreviousIfNeeded() async {
  _releasedPrevious = false; // reset por si venimos de otro ciclo

final int? toRelease = (_mode == GameMode.digits2)
    ? _lastReservedGameId2
    : (_mode == GameMode.digits3)
        ? _lastReservedGameId3
        : (_mode == GameMode.digits4)
            ? _lastReservedGameId4
            : (_mode == GameMode.quinta)
                ? _lastReservedGameId5
                : null;

  if (toRelease == null) return null;

  final res = await _gamesApi.release(
    gameId: toRelease,
    token: _authToken, // ✅ Authorization requerido por backend
    xUserId: null,     // ❌ no mezclar override
  );

  final status = res['status'] as int?;
  final code = (res['code'] ?? '').toString();

  if (res['ok'] == true) {
    _releasedPrevious = true;

    if (_mode == GameMode.digits2) {
      _lastReservedGameId2 = null;
      _lastReservedNumbers2 = null;
    } else if (_mode == GameMode.digits3) {
      _lastReservedGameId3 = null;
      _lastReservedNumbers3 = null;
    } else if (_mode == GameMode.digits4) {
      _lastReservedGameId4 = null;
      _lastReservedNumbers4 = null;
    } else if (_mode == GameMode.quinta) {
      _lastReservedGameId5 = null;
      _lastReservedNumbers5 = null;
    }



    // alias genérico del modo actual
    _lastReservedGameId = null;
    _lastReservedNumbers = null;
    return null;
  }
if (status == 404 || code == 'NOT_FOUND') {
  if (_mode == GameMode.digits2) {
    _lastReservedGameId2 = null;
  } else if (_mode == GameMode.digits3) {
    _lastReservedGameId3 = null;
  } else if (_mode == GameMode.digits4) {
    _lastReservedGameId4 = null;
  } else if (_mode == GameMode.quinta) {
    _lastReservedGameId5 = null;
  }
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

void resetToInitial() {
  bool hasRealReservation;
  if (_mode == GameMode.digits2) {
    hasRealReservation =
        _lastReservedGameId2 != null &&
        _lastReservedNumbers2 != null &&
        _lastReservedNumbers2!.length == 5;
  } else if (_mode == GameMode.digits3) {
    hasRealReservation =
        _lastReservedGameId3 != null &&
        _lastReservedNumbers3 != null &&
        _lastReservedNumbers3!.length == 5;
  } else if (_mode == GameMode.digits4) {
    hasRealReservation =
        _lastReservedGameId4 != null &&
        _lastReservedNumbers4 != null &&
        _lastReservedNumbers4!.length == 5;
  } else if (_mode == GameMode.quinta) {
    hasRealReservation =
        _lastReservedGameId5 != null &&
        _lastReservedNumbers5 != null &&
        _lastReservedNumbers5!.length == 5;
  } else {
    hasRealReservation = false;
  }


  if (hasRealReservation) {
    // Dejamos todo como está, porque ya hay números reservados
    // en este tipo de juego.
    return;
  }


  _setReserving(false);
  _displayedBalls.clear();

  // Estado vacío: 000 / 0000
 _setNumbers(List.filled(5, 0));



  _setShowFinalButtons(false);
  _setHasAddedFinal(false);
  _setHasAdded(false);
  _setShowActionIcons(false);
  _setCurrentBigBall(null);
  _setHasPlayedOnce(false);

  _gameId = null;
  _generated = const [];
  _lastReservedGameId = null;
  _lastReservedNumbers = null;

  // 👇 SOLO limpiamos el cache del modo actual
_gameIdByMode[_mode] = null;
_numbersByMode[_mode] = List.filled(5, 0);




  notifyListeners();
}

  // Permite a la Vista setear números manuales si hicieras un editor
  void setNumbersDirect(List<int> fiveNumbers) {
    if (fiveNumbers.length != 5) return;
    final maxValue = pow(10, digitsPerBall).toInt() - 1;
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
// 👇 Número ganador crudo (como viene del backend)
final rawWinning = (payload['winning_number'] ?? '').toString();

// 👇 Intentamos identificar el game_id por si necesitamos mirar el historial
final int? gameId = _toInt(
  payload['game_id'] ?? m['game_id'] ?? data['game_id'],
);

// ---------- Cálculo robusto de dígitos ----------
int digits = 0;

// 1) Intentamos obtener digits directo del payload o data
final dynamic rawDigits =
    payload['digits'] ??
    m['digits'] ??
    data['digits'] ??
    payload['numbers_digits'] ??
    data['numbers_digits'];

if (rawDigits is int) {
  digits = rawDigits;
} else if (rawDigits != null) {
  digits = int.tryParse('$rawDigits') ?? 0;
}

// 2) Si sigue en 0, intentamos deducirlo desde el historial (gamers previos)
if (digits == 0 && gameId != null) {
  final hist = _history.firstWhere(
    (h) => _toInt(h['game_id']) == gameId,
    orElse: () => const <String, dynamic>{},
  );
  if (hist.isNotEmpty) {
    final hd = hist['digits'] ?? hist['numbers_digits'];
    if (hd is int) {
      digits = hd;
    } else if (hd != null) {
      digits = int.tryParse('$hd') ?? 0;
    }
  }
}

// 3) Fallback inteligente si aún no se pudo definir digits
if (digits <= 0) {
  // a) Usamos el modo actual del tablero (3 o 4 dígitos)
  digits = digitsPerBall;

  // b) Si sigue en 0, usamos la longitud del número crudo recibido
  if (digits <= 0) {
    if (rawWinning.isNotEmpty && rawWinning.length > 3) {
      // ejemplo: "0001" o "5144" → longitud = 4
      digits = rawWinning.length;
    } else {
      // c) Último fallback seguro
      digits = 3;
    }
  }
}

// 👇 Aplicamos el formato final
final String winningFormatted =
    rawWinning.isNotEmpty ? rawWinning.padLeft(digits, '0') : rawWinning;

    return {
      'id': id ?? -1, // evita nulls
      'kind': kind,
      'title': title,
      'body': body,
      'read': read,
      'created_at': createdAt,
      'payload': payload,

      // 👇 Campos extra para que la UI pueda formatear
      'winning_raw': rawWinning,
      'digits': digits,
      'winning_formatted': winningFormatted,
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
      // 👇 número crudo que llega del backend
      final rawWinning = (data['winning_number'] ?? '').toString();

      // 👇 intentamos leer los dígitos desde el payload (por ejemplo data['digits'])
      //    si no viene, usamos 3 por defecto
      final int digits = (data['digits'] is int)
          ? data['digits'] as int
          : int.tryParse('${data['digits'] ?? ''}') ?? 3;

      // 👇 número ganador ya rellenado con ceros a la izquierda
      final formattedWinning = rawWinning.padLeft(digits, '0');

      final cand = {
        'id': id,
        'kind': kind,
        'game_id': gameId,
        'winning_number': rawWinning,           // valor crudo
        'digits': digits,                       // cuántas cifras tiene el juego
        'winning_formatted': formattedWinning,  // valor ya 000 / 0000
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

        // 👇 NUEVO: si hay ganador para el tipo de juego actual,
    // reseteamos el tablero para que vuelva a salir el botón JUGAR.
for (final m in result) {
  final int? nd = m['digits'] as int?;
  final int? gid = m['game_id'] as int?;
  if (nd == null || gid == null) continue;

  // ✅ Limpia la reserva SOLO del modo que cerró
  if (nd == 2) {
    _lastReservedGameId2 = null;
    _lastReservedNumbers2 = null;
    _gameIdByMode[GameMode.digits2] = null;
    _numbersByMode[GameMode.digits2] = List.filled(5, 0);
  } else if (nd == 3) {
    _lastReservedGameId3 = null;
    _lastReservedNumbers3 = null;
    _gameIdByMode[GameMode.digits3] = null;
    _numbersByMode[GameMode.digits3] = List.filled(5, 0);
  } else if (nd == 4) {
    _lastReservedGameId4 = null;
    _lastReservedNumbers4 = null;
    _gameIdByMode[GameMode.digits4] = null;
    _numbersByMode[GameMode.digits4] = List.filled(5, 0);
  } else if (nd == 5) {
    _lastReservedGameId5 = null;
    _lastReservedNumbers5 = null;
    _gameIdByMode[GameMode.quinta] = null;
    _numbersByMode[GameMode.quinta] = List.filled(5, 0);
  }

  // Si el modo actual es el que cerró, libera el tablero para volver a jugar
  if (nd == digitsPerBall) {
    _lastClosedGameId = gid;
    resetToInitial(); // ✅ ahora sí va a limpiar porque ya no hay "reserva real"
  }

  break;
}


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
// planDigits: 3 (cml), 4 (cm), 5 (cmu)
Future<void> applyPremiumFromStore({
  required bool premium,
  required int planDigits,
}) async {
  _isPremium = premium;

  // ✅ setea el máximo permitido por plan
  _maxDigitsAllowed = planDigits.clamp(3, 5);

  // Persiste en sesión
  await _session.setIsPremium(premium);
  await _session.setMaxDigitsAllowed(_maxDigitsAllowed); // 👈 necesitas este método

  // Si el usuario estaba en un modo no permitido, bájalo
  if (digitsPerBall > _maxDigitsAllowed && !_mode.isFreeMode) {
    if (_maxDigitsAllowed == 4) {
      setGameMode(GameMode.digits4);
    } else {
      setGameMode(GameMode.digits3);
    }
  }

  notifyListeners();
}


}
