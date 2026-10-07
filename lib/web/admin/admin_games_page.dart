// lib/web/admin/admin_games_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/core/utils/lottery_number_format.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/admin_dashboard_controller.dart';
import 'package:base_app/presentation/screens/admin_dashboard/widgets/games_bottom_sheet.dart'
    show GameRow, GameEdit, LotteryItem;

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/web_ui.dart';
import 'admin_common.dart';

enum _GameFilter { all, pending, scheduled, finished }

class AdminGamesPage extends StatefulWidget {
  final AdminDashboardController ctrl;
  const AdminGamesPage({super.key, required this.ctrl});

  @override
  State<AdminGamesPage> createState() => _AdminGamesPageState();
}

class _AdminGamesPageState extends State<AdminGamesPage> {
  final _search = TextEditingController();
  List<GameRow> _all = [];
  int _dbTotal = 0;
  bool _loading = true;
  String? _error;
  int? _busyId;
  _GameFilter _filter = _GameFilter.all;

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

  static int _toInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.ctrl.loadAllGames();
      final total = await widget.ctrl.countAllGames();
      if (!mounted) return;
      setState(() {
        _dbTotal = total;
        _all = list
            .map(
              (m) => GameRow(
                id: _toInt(m['id']),
                lotteryName: '${m['lottery_name'] ?? ''}',
                playedDate: '${m['played_date'] ?? ''}',
                playedTime: '${m['played_time'] ?? ''}',
                playersCount: _toInt(m['players_count']),
                winningNumber: m['winning_number'] == null
                    ? null
                    : _toInt(m['winning_number']),
                stateId: m['state_id'] == null ? null : _toInt(m['state_id']),
                digits: _toInt(m['digits'] ?? 3),
              ),
            )
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = prettyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _scheduled(GameRow g) =>
      g.playedDate.isNotEmpty && g.playedTime.isNotEmpty;

  /// Bloqueado si ya tiene ganador y su fecha/hora pasó (igual que la app).
  bool _isLocked(GameRow g) {
    if (g.winningNumber == null || !_scheduled(g)) return false;
    final d = DateTime.tryParse(g.playedDate);
    final p = g.playedTime.split(':');
    if (d == null || p.length < 2) return false;
    final moment = DateTime(
      d.year,
      d.month,
      d.day,
      int.tryParse(p[0]) ?? 0,
      int.tryParse(p[1]) ?? 0,
    );
    return moment.isBefore(DateTime.now());
  }

  List<GameRow> get _rows {
    final q = _search.text.trim().toLowerCase();
    return _all.where((g) {
      final ok = switch (_filter) {
        _GameFilter.all => true,
        _GameFilter.pending => !_scheduled(g) && g.winningNumber == null,
        _GameFilter.scheduled => _scheduled(g) && g.winningNumber == null,
        _GameFilter.finished => g.winningNumber != null,
      };
      if (!ok) return false;
      if (q.isEmpty) return true;
      return g.lotteryName.toLowerCase().contains(q) ||
          '${g.id}'.contains(q) ||
          g.playedDate.contains(q) ||
          (g.winningNumber != null && '${g.winningNumber}'.contains(q));
    }).toList();
  }

  String _mode(int d) => d == 5 ? 'Quinta' : '$d cifras';

  Widget _stateChip(GameRow g) {
    if (g.winningNumber != null) {
      return const StatusChip(
        label: 'Finalizado',
        color: WebPalette.emerald,
        icon: Icons.flag_rounded,
      );
    }
    if (_scheduled(g)) {
      return const StatusChip(label: 'Programado', color: WebPalette.goldLight);
    }
    return const StatusChip(label: 'Sin programar', color: WebPalette.amber);
  }

  // ───────────── Editar ─────────────

  Future<void> _edit(GameRow g) async {
    if (_isLocked(g)) {
      await WebAlerts.dialog(
        title: 'Edición bloqueada',
        message:
            'Este juego ya tiene número ganador y su fecha pasó; no se puede editar.',
        tone: AlertTone.warning,
      );
      return;
    }

    List<LotteryItem> lots = [];
    try {
      lots = await widget.ctrl.loadLotteries();
    } catch (e) {
      WebAlerts.toast(
        'No se pudo cargar el catálogo de loterías.',
        tone: AlertTone.error,
      );
    }
    if (!mounted) return;

    const custom = -99;
    final match = lots.where(
      (l) => l.name.toLowerCase() == g.lotteryName.toLowerCase(),
    );
    int? lotteryId = match.isNotEmpty
        ? match.first.id
        : (g.lotteryName.isEmpty ? null : custom);
    final customName = TextEditingController(
      text: match.isEmpty ? g.lotteryName : '',
    );
    DateTime? date = g.playedDate.isEmpty
        ? null
        : DateTime.tryParse(g.playedDate);
    TimeOfDay? time;
    final tp = g.playedTime.split(':');
    if (tp.length >= 2) {
      time = TimeOfDay(
        hour: int.tryParse(tp[0]) ?? 0,
        minute: int.tryParse(tp[1]) ?? 0,
      );
    }
    final winCtrl = TextEditingController(
      text: g.winningNumber == null
          ? ''
          : g.winningNumber.toString().padLeft(g.digits, '0'),
    );

    final ok = await showWebModal<bool>(
      context,
      title: 'Editar juego #${g.id}',
      subtitle: '${_mode(g.digits)} · ${g.playersCount} jugadores',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          String fmtDate(DateTime? d) => d == null
              ? 'Seleccionar fecha'
              : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
          String fmtTime(TimeOfDay? t) => t == null
              ? 'Seleccionar hora'
              : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                value: lotteryId,
                isExpanded: true,
                dropdownColor: WebPalette.bgElevated,
                decoration: const InputDecoration(
                  labelText: 'Lotería',
                  prefixIcon: Icon(
                    Icons.confirmation_number_outlined,
                    size: 20,
                  ),
                ),
                items: [
                  for (final l in lots)
                    DropdownMenuItem(value: l.id, child: Text(l.name)),
                  const DropdownMenuItem(
                    value: custom,
                    child: Text('Otra (escribir nombre)'),
                  ),
                ],
                onChanged: (v) => setLocal(() => lotteryId = v),
              ),
              if (lotteryId == custom) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: customName,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la lotería',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        side: BorderSide(color: WebPalette.glassBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: WebPalette.goldLight,
                      ),
                      label: Text(
                        fmtDate(date),
                        style: WebPalette.body(14, color: WebPalette.text),
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: date ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 2),
                          locale: const Locale('es', 'CO'),
                        );
                        if (p != null) setLocal(() => date = p);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        side: BorderSide(color: WebPalette.glassBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: WebPalette.goldLight,
                      ),
                      label: Text(
                        fmtTime(time),
                        style: WebPalette.body(14, color: WebPalette.text),
                      ),
                      onPressed: () async {
                        final p = await showTimePicker(
                          context: ctx,
                          initialTime: time ?? TimeOfDay.now(),
                        );
                        if (p != null) setLocal(() => time = p);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: winCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(g.digits),
                ],
                decoration: InputDecoration(
                  labelText: 'Número ganador (opcional)',
                  helperText:
                      'Debe tener ${g.digits} cifras. Al publicarlo se notifica a los jugadores.',
                  prefixIcon: const Icon(Icons.emoji_events_outlined, size: 20),
                ),
              ),
              ModalActions(
                okText: 'Guardar cambios',
                onOk: () {
                  final w = winCtrl.text.trim();
                  if (w.isNotEmpty && w.length != g.digits) {
                    WebAlerts.toast(
                      'El número ganador debe tener ${g.digits} cifras.',
                      tone: AlertTone.warning,
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;

    final newDate = date == null
        ? null
        : '${date!.year.toString().padLeft(4, '0')}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}';
    final newTime = time == null
        ? null
        : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}';
    final isCustom = lotteryId == custom;
    final winning = int.tryParse(winCtrl.text.trim());

    setState(() => _busyId = g.id);
    try {
      await widget.ctrl.updateGame(
        g.id,
        GameEdit(
          lotteryId: isCustom ? null : lotteryId,
          customLotteryName: isCustom && customName.text.trim().isNotEmpty
              ? customName.text.trim()
              : null,
          playedDate: newDate ?? (g.playedDate.isEmpty ? null : g.playedDate),
          playedTime: newTime ?? (g.playedTime.isEmpty ? null : g.playedTime),
        ),
      );
      if (winning != null && winning != g.winningNumber) {
        await widget.ctrl.setGameWinner(g.id, winning);
      }
      WebAlerts.toast(
        'El juego #${g.id} fue actualizado.',
        tone: AlertTone.success,
      );
      await _load();
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo actualizar',
        message: prettyError(e),
        tone: AlertTone.error,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(GameRow g) async {
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: 'Eliminar juego',
      message:
          '¿Deseas eliminar el juego #${g.id}? Esta acción no se puede deshacer.',
      okText: 'Sí, eliminar',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok) return;
    setState(() => _busyId = g.id);
    try {
      await widget.ctrl.deleteGame(g.id);
      setState(() {
        _all.removeWhere((x) => x.id == g.id);
        if (_dbTotal > 0) _dbTotal--;
      });
      WebAlerts.toast('Juego #${g.id} eliminado.', tone: AlertTone.success);
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo eliminar',
        message: prettyError(e),
        tone: AlertTone.error,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final finished = _all.where((g) => g.winningNumber != null).length;
    final scheduled = _all
        .where((g) => _scheduled(g) && g.winningNumber == null)
        .length;
    final players = _all.fold<int>(0, (a, g) => a + g.playersCount);

    return WebPage(
      children: [
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            StatTile(
              label: 'Juegos en total',
              value: '$_dbTotal',
              icon: Icons.casino_outlined,
            ),
            StatTile(
              label: 'Programados',
              value: '$scheduled',
              icon: Icons.event_available_rounded,
              color: WebPalette.goldLight,
            ),
            StatTile(
              label: 'Finalizados',
              value: '$finished',
              icon: Icons.flag_outlined,
              color: WebPalette.emerald,
            ),
            StatTile(
              label: 'Participaciones',
              value: '$players',
              icon: Icons.groups_outlined,
              color: WebPalette.violet,
            ),
          ],
        ),
        const SizedBox(height: 22),
        WebPanel(
          title: 'Juegos',
          subtitle:
              'Programa la lotería, fecha y hora y publica el número ganador',
          icon: Icons.casino_outlined,
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
                hint: 'Buscar por #, lotería, fecha o ganador',
                onSearch: (_) => setState(() {}),
                filters: [
                  WebSegmented<_GameFilter>(
                    options: const [
                      (_GameFilter.all, 'Todos'),
                      (_GameFilter.pending, 'Sin programar'),
                      (_GameFilter.scheduled, 'Programados'),
                      (_GameFilter.finished, 'Finalizados'),
                    ],
                    value: _filter,
                    onChanged: (v) => setState(() => _filter = v),
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
                  title: 'Sin juegos para mostrar',
                )
              else
                WebTable<GameRow>(
                  rows: rows,
                  onRowTap: _edit,
                  mobileTitle: (g) => Text(
                    'Juego #${g.id}',
                    style: WebPalette.display(15, weight: FontWeight.w700),
                  ),
                  trailing: (g) => RowActions(
                    busy: _busyId == g.id,
                    actions: [
                      RowAction(
                        Icons.edit_calendar_outlined,
                        'Programar / editar',
                        () => _edit(g),
                        enabled: !_isLocked(g),
                      ),
                      RowAction(
                        Icons.delete_outline_rounded,
                        'Eliminar',
                        () => _delete(g),
                        danger: true,
                      ),
                    ],
                  ),
                  columns: [
                    WebColumn(
                      'Juego',
                      (g) => CellText('#${g.id}', strong: true),
                      flex: 1,
                    ),
                    WebColumn(
                      'Modalidad',
                      (g) => CellText(_mode(g.digits)),
                      flex: 2,
                    ),
                    WebColumn(
                      'Lotería',
                      (g) => CellText(
                        g.lotteryName.isEmpty ? 'Por definir' : g.lotteryName,
                      ),
                      flex: 3,
                    ),
                    WebColumn(
                      'Fecha',
                      (g) => CellText(
                        [
                          g.playedDate,
                          g.playedTime,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      flex: 2,
                    ),
                    WebColumn(
                      'Jugadores',
                      (g) => CellText('${g.playersCount}'),
                      flex: 1,
                    ),
                    WebColumn(
                      'Ganador',
                      (g) => CellText(
                        g.winningNumber == null
                            ? '—'
                            : formatGameNumber(g.winningNumber!, g.digits),
                        mono: true,
                      ),
                      flex: 1,
                    ),
                    WebColumn('Estado', _stateChip, flex: 2),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
