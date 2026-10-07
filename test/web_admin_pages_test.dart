// Pruebas de render de las páginas web del panel admin con datos simulados.
// Verifican que se dibujan sin errores de diseño en escritorio y en móvil.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:base_app/presentation/screens/admin_dashboard/logic/admin_dashboard_controller.dart';
import 'package:base_app/web/admin/admin_games_page.dart';
import 'package:base_app/web/admin/admin_players_page.dart';
import 'package:base_app/web/admin/admin_users_page.dart';
import 'package:base_app/web/theme/web_theme.dart';

class _FakeAdminCtrl extends AdminDashboardController {
  _FakeAdminCtrl() : super(baseUrl: 'http://test');

  @override
  Future<List<Map<String, dynamic>>> loadAllGames({String q = '', int page = 1}) async => [
        {
          'id': 1,
          'lottery_name': 'Lotería de Bogotá',
          'played_date': '2026-10-10',
          'played_time': '22:30',
          'players_count': 5,
          'winning_number': null,
          'state_id': 1,
          'digits': 3,
        },
        {
          'id': 2,
          'lottery_name': '',
          'played_date': '',
          'played_time': '',
          'players_count': 1,
          'winning_number': 42,
          'state_id': 2,
          'digits': 2,
        },
      ];

  @override
  Future<int> countAllGames({String q = ''}) async => 2;

  @override
  Future<List<Map<String, dynamic>>> loadAllPlayers({
    String q = '',
    String state = 'active',
    int page = 1,
  }) async =>
      [
        {
          'user_id': 2,
          'player_name': 'Usuario Prueba',
          'code': 'USER0002',
          'game_id': 2,
          'lottery_name': '',
          'played_date': '',
          'played_time': '',
          'numbers': [87, 90, 19, 21, 43],
          'digits': 2,
        },
      ];

  @override
  Future<int> countAllPlayers({String q = '', String state = 'active'}) async => 1;

  @override
  Future<List<Map<String, dynamic>>> loadAllUsers({String q = '', int page = 1}) async => [
        {
          'id': 1,
          'name': 'Admin Prueba',
          'phone': '3000000001',
          'public_code': 'ADMIN001',
          'role_id': 1,
          'role': 'Administrador',
          'subscription': '-',
          'subscription_status': 'none',
        },
        {
          'id': 2,
          'name': 'Usuario Prueba',
          'phone': '3000000002',
          'public_code': 'USER0002',
          'role_id': 2,
          'role': 'Usuario',
          'subscription': 'PRO',
          'subscription_status': 'active',
        },
      ];
}

Future<void> _pump(WidgetTester tester, Widget page, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: buildWebTheme(), home: Scaffold(body: page)),
  );
  // Deja resolver las cargas simuladas y avanzar animaciones de carga.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final size in const [Size(1440, 900), Size(390, 844)]) {
    final label = size.width > 600 ? 'escritorio' : 'móvil';

    testWidgets('Juegos se dibuja sin errores ($label)', (tester) async {
      await _pump(tester, AdminGamesPage(ctrl: _FakeAdminCtrl()), size);
      expect(find.text('Lotería de Bogotá'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Jugadores se dibuja sin errores ($label)', (tester) async {
      await _pump(tester, AdminPlayersPage(ctrl: _FakeAdminCtrl()), size);
      expect(find.text('Usuario Prueba'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Usuarios se dibuja sin errores ($label)', (tester) async {
      await _pump(tester, AdminUsersPage(ctrl: _FakeAdminCtrl()), size);
      expect(find.text('Admin Prueba'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
