// lib/web/admin/admin_players_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/admin_dashboard_controller.dart';
import 'package:base_app/presentation/screens/admin_dashboard/widgets/players_bottom_sheet.dart'
    show PlayerRow;

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/web_ui.dart';
import 'admin_common.dart';

class AdminPlayersPage extends StatefulWidget {
  final AdminDashboardController ctrl;
  const AdminPlayersPage({super.key, required this.ctrl});

  @override
  State<AdminPlayersPage> createState() => _AdminPlayersPageState();
}

class _AdminPlayersPageState extends State<AdminPlayersPage> {
  final _search = TextEditingController();
  String _state = 'active';
  int? _digits; // filtro de modalidad
  List<PlayerRow> _all = [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.ctrl.loadAllPlayers(state: _state);
      final total = await widget.ctrl.countAllPlayers(state: _state);
      if (!mounted) return;
      setState(() {
        _total = total;
        _all = list.map<PlayerRow>((m) {
          final d = (m['digits'] as num?)?.toInt() ?? 3;
          String pad(dynamic e) {
            final s = e.toString();
            final neg = s.startsWith('-');
            final core = (neg ? s.substring(1) : s).padLeft(d, '0');
            return neg ? '-$core' : core;
          }

          return PlayerRow(
            id: (m['user_id'] as num).toInt(),
            name: '${m['player_name'] ?? ''}',
            code: '${m['code'] ?? m['public_code'] ?? ''}',
            gameId: (m['game_id'] as num).toInt(),
            lotteryName: '${m['lottery_name'] ?? ''}',
            playedDate: '${m['played_date'] ?? ''}',
            playedTime: '${m['played_time'] ?? ''}',
            numbers: (m['numbers'] as List? ?? const []).map(pad).toList(),
            digits: d,
          );
        }).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = prettyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PlayerRow> get _rows {
    final q = _search.text.trim().toLowerCase();
    return _all.where((p) {
      if (_digits != null && p.digits != _digits) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q) ||
          '${p.gameId}'.contains(q) ||
          p.lotteryName.toLowerCase().contains(q) ||
          p.numbers.any((n) => n.contains(q));
    }).toList();
  }

  String _key(PlayerRow p) => '${p.id}-${p.gameId}';

  Future<void> _editNumbers(PlayerRow p) async {
    final ctrls = [for (final n in p.numbers) TextEditingController(text: n)];
    final formKey = GlobalKey<FormState>();

    final ok = await showWebModal<bool>(
      context,
      title: 'Editar balotas',
      subtitle: '${p.name} · Juego #${p.gameId} · ${p.digits} cifras',
      builder: (ctx) => Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < ctrls.length; i++)
                  SizedBox(
                    width: 150,
                    child: TextFormField(
                      controller: ctrls[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: WebPalette.display(
                        18,
                        weight: FontWeight.w700,
                        color: WebPalette.goldLight,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(p.digits),
                      ],
                      decoration: InputDecoration(labelText: 'Balota ${i + 1}'),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Requerido';
                        if (s.length != p.digits) return '${p.digits} dígitos';
                        return null;
                      },
                    ),
                  ),
              ],
            ),
            ModalActions(
              okText: 'Guardar balotas',
              onOk: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop(true);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final nums = [for (final c in ctrls) c.text.trim().padLeft(p.digits, '0')];
    setState(() => _busyKey = _key(p));
    try {
      final returned = await widget.ctrl.updatePlayerNumbers(
        userId: p.id,
        gameId: p.gameId,
        numbers: nums,
      );
      setState(() {
        final i = _all.indexWhere((x) => _key(x) == _key(p));
        if (i != -1) {
          _all[i] = _all[i].copyWith(
            numbers: returned.isNotEmpty ? returned : nums,
          );
        }
      });
      WebAlerts.toast(
        'Las balotas de ${p.name} fueron actualizadas.',
        tone: AlertTone.success,
      );
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo actualizar',
        message: prettyError(e),
        tone: AlertTone.error,
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _delete(PlayerRow p) async {
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: 'Eliminar participación',
      message: '¿Eliminar los números de ${p.name} en el juego #${p.gameId}?',
      okText: 'Sí, eliminar',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok) return;
    setState(() => _busyKey = _key(p));
    try {
      await widget.ctrl.deletePlayerNumbers(userId: p.id, gameId: p.gameId);
      setState(() {
        _all.removeWhere((x) => _key(x) == _key(p));
        if (_total > 0) _total--;
      });
      WebAlerts.toast('Participación eliminada.', tone: AlertTone.success);
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo eliminar',
        message: prettyError(e),
        tone: AlertTone.error,
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final active = _state == 'active';

    return WebPage(
      children: [
        WebPanel(
          title: 'Jugadores',
          subtitle: active
              ? '$_total participaciones en juegos activos'
              : '$_total participaciones históricas',
          icon: Icons.sports_esports_outlined,
          actions: [
            WebIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Actualizar',
              onPressed: _loading ? null : _load,
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TableToolbar(
                search: _search,
                hint: 'Buscar por nombre, código, juego o número',
                onSearch: (_) => setState(() {}),
                filters: [
                  WebSegmented<String>(
                    options: const [
                      ('active', 'Activos'),
                      ('historical', 'Histórico'),
                    ],
                    value: _state,
                    onChanged: (v) {
                      setState(() => _state = v);
                      _load();
                    },
                  ),
                  WebSegmented<int?>(
                    options: const [
                      (null, 'Todas'),
                      (2, '2 cifras'),
                      (3, '3 cifras'),
                      (4, '4 cifras'),
                      (5, 'Quinta'),
                    ],
                    value: _digits,
                    onChanged: (v) => setState(() => _digits = v),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading)
                const TableSkeleton()
              else if (_error != null)
                EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'No se pudo cargar',
                  message: _error,
                )
              else if (rows.isEmpty)
                const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Sin jugadores para mostrar',
                )
              else
                WebTable<PlayerRow>(
                  rows: rows,
                  mobileTitle: (p) => Text(
                    p.name,
                    style: WebPalette.display(15, weight: FontWeight.w700),
                  ),
                  trailing: (p) => RowActions(
                    busy: _busyKey == _key(p),
                    actions: [
                      if (active)
                        RowAction(
                          Icons.edit_outlined,
                          'Editar balotas',
                          () => _editNumbers(p),
                        ),
                      RowAction(
                        Icons.delete_outline_rounded,
                        'Eliminar',
                        () => _delete(p),
                        danger: true,
                      ),
                    ],
                  ),
                  columns: [
                    WebColumn(
                      'Jugador',
                      (p) => CellText(p.name, strong: true),
                      flex: 3,
                    ),
                    WebColumn(
                      'Código',
                      (p) => CellText(p.code, mono: true),
                      flex: 2,
                    ),
                    WebColumn(
                      'Juego',
                      (p) => CellText('#${p.gameId}'),
                      flex: 1,
                    ),
                    WebColumn(
                      'Números',
                      (p) => NumberPills(p.numbers),
                      flex: 5,
                    ),
                    WebColumn(
                      'Lotería',
                      (p) => CellText(
                        p.lotteryName.isEmpty ? 'Por definir' : p.lotteryName,
                      ),
                      flex: 2,
                    ),
                    WebColumn(
                      'Fecha',
                      (p) => CellText(
                        [
                          p.playedDate,
                          p.playedTime,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      flex: 2,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
