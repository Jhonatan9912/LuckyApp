// lib/presentation/screens/admin_dashboard/logic/admin_dashboard_controller.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:base_app/data/session/session_manager.dart';
import '../widgets/games_bottom_sheet.dart' show GameEdit, GameRow, LotteryItem;

class AdminDashboardController extends ChangeNotifier {
  bool loading = false;
  String? error;

  Map<String, dynamic>? kpis;
  List<Map<String, dynamic>> loansByMonth = []; // gráfico 1 (usamos 'cnt')
  List<Map<String, dynamic>> interestByMonth =
      []; // gráfico 2 (usamos 'interest')
  List<Map<String, dynamic>> latestUsers = [];
  List<Map<String, dynamic>> latestPayments = [];

  final String baseUrl;
  AdminDashboardController({this.baseUrl = 'http://10.0.2.2:8000'});

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final token = await SessionManager().getToken();
      final uri = Uri.parse('$baseUrl/api/admin/dashboard/summary');
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      // ⬇️ imprime siempre
      debugPrint('[summary] ${res.statusCode} ${res.body}', wrapWidth: 1024);

      if (res.statusCode != 200) {
        error = 'Error ${res.statusCode}: ${res.body}';
        loading = false;
        notifyListeners();
        return;
      }

      final Map<String, dynamic> data = json.decode(res.body);

      // === KPIs SOLO: Usuarios y Juegos ===
      final k = (data['kpis'] as Map?)?.cast<String, dynamic>() ?? {};
      kpis = {
        'users': k['users'] ?? k['total_users'] ?? k['usuarios'] ?? 0,
        'games': k['games'] ?? k['total_games'] ?? k['juegos'] ?? 0,
        'players': k['players'] ?? k['total_players'] ?? k['jugadores'] ?? 0,
      };

      // === Listas del backend: sales_by_month, revenue_by_month, latest_users, latest_sales ===
      final List salesByMonthRaw =
          (data['sales_by_month'] as List?) ?? const [];
      final List revenueByMonthRaw =
          (data['revenue_by_month'] as List?) ?? const [];
      final List latestUsersRaw = (data['latest_users'] as List?) ?? const [];
      final List latestSalesRaw = (data['latest_sales'] as List?) ?? const [];

      // LoansByMonthChart -> usa {month, cnt}
      loansByMonth = salesByMonthRaw.map<Map<String, dynamic>>((e) {
        final m = (e as Map).cast<String, dynamic>();
        return {'month': m['month'] ?? '', 'cnt': (m['qty'] ?? 0) as num};
      }).toList();

      // InterestByMonthChart -> usa {month, interest}
      interestByMonth = revenueByMonthRaw.map<Map<String, dynamic>>((e) {
        final m = (e as Map).cast<String, dynamic>();
        return {
          'month': m['month'] ?? '',
          'interest': (m['revenue'] ?? 0) as num,
        };
      }).toList();

      latestUsers = latestUsersRaw.map<Map<String, dynamic>>((e) {
        final m = (e as Map).cast<String, dynamic>();
        return {
          'name': m['name'] ?? '',
          'identification_number': m['identification_number'] ?? '',
          'phone': m['phone'] ?? '',
        };
      }).toList();

      // Reutilizamos "Últimos Pagos" para mostrar ventas
      latestPayments = latestSalesRaw.map<Map<String, dynamic>>((e) {
        final m = (e as Map).cast<String, dynamic>();
        return {
          'loan_id': m['sale_id'], // etiqueta existente en tu UI
          'payment_value': m['total_amount'] ?? 0, // monto de la venta
          'payment_date': m['sale_date'] ?? '', // fecha
        };
      }).toList();
    } catch (e) {
      error = 'Error: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Carga lista de usuarios desde /api/admin/users
  Future<List<Map<String, String>>> loadAllUsers({
    String q = '',
    int page = 1,
  }) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/users').replace(
      queryParameters: {
        if (q.isNotEmpty) 'q': q,
        'page': '$page',
        'per_page': '50',
      },
    );

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      // ignore: avoid_print
      print('[admin/users] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    final List items = (body['items'] as List?) ?? const [];

    return items.map<Map<String, String>>((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final roleName = (m['role'] ?? '').toString();
      return {
        'id': (m['id'] ?? '').toString(), // ← necesario
        'name': (m['name'] ?? '').toString(),
        'phone': (m['phone'] ?? '').toString(),
        'role': roleName,
        'role_id': (m['role_id'] ?? '').toString(), // ← necesario
        'code': (m['public_code'] ?? '').toString(),
      };
    }).toList();
  }

  /// Devuelve un Map con: id, name, phone, public_code, role_id, role
  Future<Map<String, dynamic>> updateUserRole(int userId, int newRoleId) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/users/$userId/role');

    final res = await http
        .patch(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode({'role_id': newRoleId}),
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      // ignore: avoid_print
      print('[PATCH users/$userId/role] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;

    // backend recomendado: { ok:true, item:{...} }
    final Map<String, dynamic> item =
        (body['item'] as Map?)?.cast<String, dynamic>() ??
        body.cast<String, dynamic>();

    return {
      'id': item['id'],
      'name': item['name'],
      'phone': item['phone'],
      'public_code': item['public_code'],
      'role_id': item['role_id'],
      'role':
          item['role'] ??
          ((item['role_id'] == 1) ? 'Administrador' : 'Usuario'),
    };
  }

  /// Elimina al usuario en backend: DELETE /api/admin/users/:id
  Future<void> deleteUser(int userId) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/users/$userId');

    final res = await http
        .delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      print('[DELETE users/$userId] ${res.statusCode} ${res.body}');
    }

    // Si no es 2xx, extrae SOLO el mensaje humano del backend
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg;
      try {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final List errs = (body['errors'] as List?) ?? const [];
        msg =
            (body['error'] ??
                    body['message'] ??
                    body['detail'] ??
                    (errs.isNotEmpty ? errs.join('\n') : null))
                ?.toString() ??
            'No se pudo eliminar el usuario.';
      } catch (_) {
        msg = 'No se pudo eliminar el usuario.';
      }
      throw Exception(msg);
    }
  }

  /// Lista de juegos: GET /api/admin/games
  Future<List<Map<String, dynamic>>> loadAllGames({
    String q = '',
    int page = 1,
  }) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/games').replace(
      queryParameters: {
        if (q.isNotEmpty) 'q': q,
        'page': '$page',
        'per_page': '50',
      },
    );

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      // ignore: avoid_print
      print('[admin/games] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    final List items = (body['items'] as List?) ?? const [];

    // Normalizamos campos esperados por la UI
    return items.map<Map<String, dynamic>>((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return {
        'id': m['id'],
        'lottery_name': m['lottery_name'] ?? '',
        'played_date': m['played_date'] ?? '',
        'played_time': m['played_time'] ?? '',
        'players_count': m['players_count'] ?? 0,
        'winning_number': m['winning_number'], // 👈 nuevo
        'state_id': m['state_id'], // 👈 nuevo
      };
    }).toList();
  }

  /// Cuenta juegos en DB usando el mismo endpoint (lee el campo "total").
  Future<int> countAllGames({String q = ''}) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/games').replace(
      queryParameters: {
        if (q.isNotEmpty) 'q': q,
        'page': '1',
        'per_page': '1', // no necesitamos items, solo el total
      },
    );

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      // ignore: avoid_print
      print('[admin/games:count] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    return (body['total'] as num?)?.toInt() ?? 0;
  }

  /// Catálogo de loterías para el select: GET /api/admin/games/lotteries
  Future<List<LotteryItem>> loadLotteries() async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/games/lotteries');

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      // ignore: avoid_print
      print('[admin/games/lotteries] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    final List items = (body['items'] as List?) ?? const [];

    return items.map<LotteryItem>((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return LotteryItem(
        id: int.tryParse('${m['id']}') ?? 0,
        name: (m['name'] ?? '').toString(),
      );
    }).toList();
  }

  /// Elimina un juego: DELETE /api/admin/games/:id
  Future<void> deleteGame(int gameId) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/games/$gameId');

    final res = await http
        .delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      // ignore: avoid_print
      print('[DELETE games/$gameId] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

Future<GameRow?> updateGame(int gameId, GameEdit input) async {
  final token = await SessionManager().getToken();
  final uri = Uri.parse('$baseUrl/api/admin/games/$gameId');

  final res = await http
      .patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(input.toJson()), // 👈 usa toJson con todos los campos
      )
      .timeout(const Duration(seconds: 15));

  if (kDebugMode) {
    print('[PATCH games/$gameId] ${res.statusCode} ${res.body}');
  }

  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }

  final Map<String, dynamic> data =
      json.decode(res.body) as Map<String, dynamic>;
  final Map<String, dynamic> item =
      (data['item'] as Map?)?.cast<String, dynamic>() ??
      data.cast<String, dynamic>();

  int toInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;
  String toStr(dynamic v) => v?.toString() ?? '';

  return GameRow(
    id: toInt(item['id']),
    lotteryName: toStr(item['lottery_name']),
    playedDate: toStr(item['played_date']),
    playedTime: toStr(item['played_time']),
    playersCount: toInt(item['players_count']),
    winningNumber: item['winning_number'] == null
        ? null
        : toInt(item['winning_number']),
    stateId: item['state_id'] == null ? null : toInt(item['state_id']),
  );
}

  Future<GameRow?> setGameWinner(int gameId, int winningNumber) async {
  final token = await SessionManager().getToken();
  final uri = Uri.parse('$baseUrl/api/admin/games/$gameId/winner');

  final res = await http
      .post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'winning_number': winningNumber}),
      )
      .timeout(const Duration(seconds: 15));

  if (kDebugMode) {
    // ignore: avoid_print
    print('[POST games/$gameId/winner] ${res.statusCode} ${res.body}');
  }

  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }

  final Map<String, dynamic> data =
      json.decode(res.body) as Map<String, dynamic>;
  final Map<String, dynamic> item =
      (data['item'] as Map?)?.cast<String, dynamic>() ?? data.cast<String, dynamic>();

  int toInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;
  String toStr(dynamic v) => v?.toString() ?? '';

  return GameRow(
    id: toInt(item['id']),
    lotteryName: toStr(item['lottery_name']),
    playedDate: toStr(item['played_date']),
    playedTime: toStr(item['played_time']),
    playersCount: toInt(item['players_count']),
    winningNumber: item['winning_number'] == null ? null : toInt(item['winning_number']),
    stateId: item['state_id'] == null ? null : toInt(item['state_id']),
  );
}

  /// === JUGADORES: GET /api/admin/players ================================

  Future<List<Map<String, dynamic>>> loadAllPlayers({
    String q = '',
    int page = 1,
  }) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/players').replace(
      queryParameters: {
        if (q.isNotEmpty) 'q': q,
        'page': '$page',
        'per_page': '50',
      },
    );

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      print('[admin/players] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    final List items = (body['items'] as List?) ?? const [];

    // Normalizamos lo que usará PlayersBottomSheet
    return items.map<Map<String, dynamic>>((e) {
      final m = Map<String, dynamic>.from(e as Map);
      // Aseguramos que 'numbers' sea List<String>
      final nums = (m['numbers'] as List? ?? const [])
          .map((x) => x?.toString() ?? '')
          .toList();

      return {
        'user_id': m['user_id'],
        'player_name': m['player_name'] ?? '',
        'public_code': m['code'] ?? m['public_code'] ?? '', // ← importante
        'game_id': m['game_id'],
        'lottery_name': m['lottery_name'] ?? '',
        'played_date': m['played_date'] ?? '',
        'played_time': m['played_time'] ?? '',
        'numbers': nums,
      };
    }).toList();
  }

  /// Cuenta jugadores agrupados (user_id + game_id) usando el mismo endpoint
  Future<int> countAllPlayers({String q = ''}) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse('$baseUrl/api/admin/players').replace(
      queryParameters: {if (q.isNotEmpty) 'q': q, 'page': '1', 'per_page': '1'},
    );

    final res = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      print('[admin/players:count] ${res.statusCode} ${res.body}');
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    return (body['total'] as num?)?.toInt() ?? 0;
  }

  /// DELETE: elimina TODAS las balotas del jugador (userId) en ese juego (gameId)
  Future<void> deletePlayerNumbers({
    required int userId,
    required int gameId,
  }) async {
    final token = await SessionManager().getToken();
    final uri = Uri.parse(
      '$baseUrl/api/admin/players/$userId/games/$gameId/numbers',
    );

    final res = await http
        .delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (kDebugMode) {
      print(
        '[DELETE players/$userId/games/$gameId/numbers] '
        '${res.statusCode} ${res.body}',
      );
    }

    // 423: juego bloqueado por fecha/hora
    if (res.statusCode == 423) {
      String msg;
      try {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        msg =
            (body['error'] ??
                    body['message'] ??
                    body['detail'] ??
                    'El juego ya comenzó o está cerrado; no se pueden eliminar balotas.')
                .toString();
      } catch (_) {
        msg =
            'El juego ya comenzó o está cerrado; no se pueden eliminar balotas.';
      }
      throw Exception(msg);
    }

    // Cualquier otro error
    if (res.statusCode != 200) {
      String msg;
      try {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final List errs = (body['errors'] as List?) ?? const [];
        msg =
            (body['error'] ??
                    body['message'] ??
                    body['detail'] ??
                    (errs.isNotEmpty ? errs.join('\n') : null))
                ?.toString() ??
            'Error ${res.statusCode} al eliminar balotas.';
      } catch (_) {
        msg = 'Error ${res.statusCode} al eliminar balotas.';
      }
      throw Exception(msg);
    }
  }

  Future<List<String>> updatePlayerNumbers({
    required int userId,
    required int gameId,
    required List<String> numbers,
  }) async {
    final normalized = numbers.map((n) => n.trim().padLeft(3, '0')).toList();

    final token = await SessionManager().getToken();
    final uri = Uri.parse(
      '$baseUrl/api/admin/players/$userId/games/$gameId/numbers',
    );

    final res = await http
        .patch(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode({'numbers': normalized}),
        )
        .timeout(const Duration(seconds: 15));

    // 423: juego bloqueado por fecha/hora
    if (res.statusCode == 423) {
      String msg;
      try {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        msg =
            (body['error'] ??
                    body['message'] ??
                    body['detail'] ??
                    'El juego ya comenzó o está cerrado; no se pueden editar balotas.')
                .toString();
      } catch (_) {
        msg =
            'El juego ya comenzó o está cerrado; no se pueden editar balotas.';
      }
      throw Exception(msg);
    }

    // 409: conflicto con números ya tomados por OTRO jugador
    if (res.statusCode == 409) {
      try {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final List conflict = (body['conflict'] as List?) ?? const [];
        final txt = conflict
            .map((e) => e.toString().padLeft(3, '0'))
            .join(', ');
        throw Exception(
          'Los siguientes números ya están reservados en este juego: $txt',
        );
      } catch (_) {
        throw Exception(
          'Algunas balotas ya están reservadas por otro jugador.',
        );
      }
    }

    // 4xx/5xx: toma sólo el mensaje humano del backend
    if (res.statusCode >= 400) {
      String msg;
      try {
        final Map<String, dynamic> body =
            json.decode(res.body) as Map<String, dynamic>;
        final List errs = (body['errors'] as List?) ?? const [];
        msg =
            (body['error'] ??
                    body['message'] ??
                    body['detail'] ??
                    (errs.isNotEmpty ? errs.join('\n') : null))
                ?.toString() ??
            'Error ${res.statusCode} al actualizar balotas.';
      } catch (_) {
        msg = 'Error ${res.statusCode} al actualizar balotas.';
      }
      throw Exception(msg);
    }

    // OK
    final Map<String, dynamic> body =
        json.decode(res.body) as Map<String, dynamic>;
    final List returned = (body['numbers'] as List?) ?? const [];
    return returned.map((e) => e.toString().padLeft(3, '0')).toList();
  }
}
