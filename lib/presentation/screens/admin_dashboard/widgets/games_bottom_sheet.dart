import 'dart:async';
import 'package:flutter/material.dart';
import 'package:base_app/core/ui/dialogs.dart' as custom;
import 'package:flutter/services.dart';

/// BottomSheet de Juegos (estructura igual al de Usuarios).
class GamesBottomSheet extends StatefulWidget {
  /// Carga la lista de juegos.
  /// Debe mapear: id, lottery_name, played_date (YYYY-MM-DD), played_time (HH:MM), players_count.
  final Future<List<GameRow>> Function({String q}) loader;
  final Future<int> Function({String q})? countLoader;

  /// Carga el catálogo de loterías para el select (id + name).
  final Future<List<LotteryItem>> Function() loadLotteries;

  /// Actualiza un juego en backend (opcional). Si retorna GameRow, se reemplaza en la lista.
  final Future<GameRow?> Function(int gameId, GameEdit input)? onUpdate;
  final Future<GameRow?> Function(int gameId, int winningNumber)? onSetWinner;

  /// Elimina un juego en backend (opcional).
  final Future<void> Function(int gameId)? onDelete;

  const GamesBottomSheet({
    super.key,
    required this.loader,
    required this.loadLotteries,
    this.onUpdate,
    this.onDelete,
    this.countLoader,
    this.onSetWinner,
  });

  @override
  State<GamesBottomSheet> createState() => _GamesBottomSheetState();
}

class _GamesBottomSheetState extends State<GamesBottomSheet> {
  List<GameRow> _all = [];
  String _q = '';
  bool _loading = true;
  int _dbTotal = 0;
  int? _deletingId;
  int? _savingId; // para deshabilitar mientras se guarda

  // 🔒 Devuelve true si: HAY número ganador y el (día+hora) del juego ya pasó.
  bool _isLocked(GameRow g) {
    if (g.winningNumber == null) return false; // sin ganador -> editable
    if (g.playedDate.isEmpty || g.playedTime.isEmpty) return false;

    final date = DateTime.tryParse(g.playedDate);
    if (date == null) return false;

    final parts = g.playedTime.split(':');
    if (parts.length < 2) return false;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    final gameMoment = DateTime(date.year, date.month, date.day, h, m);
    final now = DateTime.now();

    return gameMoment.isBefore(now);
  }

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_refresh);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _deletingId = null;
      _savingId = null;
    });
    try {
      final data = await widget.loader(q: _q);
      int total;
      if (widget.countLoader != null) {
        total = await widget.countLoader!(q: '');
      } else {
        total = data.length;
      }

      if (!mounted) return;
      setState(() {
        _all = data;
        _dbTotal = total;
      });
    } catch (e) {
      if (!mounted) return;
      await custom.AppDialogs.error(
        context: context,
        title: 'Error',
        message: 'No se pudo cargar la lista de juegos.\n$e',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelete(GameRow g) async {
    if (widget.onDelete == null) return;
    final ok = await custom.AppDialogs.confirm(
      context: context,
      title: 'Eliminar juego',
      message:
          '¿Deseas eliminar el juego #${g.id}? Esta acción no se puede deshacer.',
      okText: 'Sí, eliminar',
      cancelText: 'Cancelar',
      destructive: true,
      icon: Icons.delete_forever,
    );
    if (!mounted || !ok) return;

    try {
      setState(() => _deletingId = g.id);
      await widget.onDelete!(g.id);
      if (!mounted) return;
      setState(() {
        _all.removeWhere((x) => x.id == g.id);
        if (widget.countLoader != null && _dbTotal > 0) {
          _dbTotal -= 1;
        }
        _deletingId = null;
      });

      if (!mounted) return;
      await custom.AppDialogs.success(
        context: context,
        title: 'Eliminado',
        message: 'El juego fue eliminado correctamente.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      await custom.AppDialogs.error(
        context: context,
        title: 'Error',
        message: 'Error al eliminar: $e',
      );
    }
  }

  Future<void> _openEdit(GameRow g) async {
    // 🔒 No permitir edición si está bloqueado
    if (_isLocked(g)) {
      await custom.AppDialogs.error(
        context: context,
        title: 'Edición bloqueada',
        message:
            'Este juego ya tiene número ganador y su fecha es anterior a hoy; no se puede editar.',
      );
      return;
    }

    // Traer loterías para el select
    List<LotteryItem> lots = [];
    try {
      lots = await widget.loadLotteries();
    } catch (e) {
      if (!mounted) return;
      await custom.AppDialogs.error(
        context: context,
        title: 'Catálogo',
        message: 'No se pudo cargar el catálogo de loterías.\n$e',
      );
    }

    DateTime? selDate =
        g.playedDate.isEmpty ? null : DateTime.tryParse(g.playedDate);

    TimeOfDay? selTime;
    if (g.playedTime.isNotEmpty) {
      final parts = g.playedTime.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          selTime = TimeOfDay(hour: h, minute: m);
        }
      }
    }

    int? selWinning = g.winningNumber;

    // Preseleccionar lotería por nombre
    int? selLotteryId;
    if (lots.isNotEmpty) {
      final match = lots.firstWhere(
        (it) => it.name.toLowerCase() == g.lotteryName.toLowerCase(),
        orElse: () => const LotteryItem(id: -1, name: ''),
      );
      selLotteryId = (match.id == -1) ? null : match.id;
    }
    if (!mounted) return;

    // === CONTROL DE GANADOR (3 o 4 dígitos según el juego) ==================
    final int digits = g.digits; // 3 ó 4
    final winnerCtrl = TextEditingController(
      text: (g.winningNumber == null)
          ? ''
          : g.winningNumber!.toString().padLeft(digits, '0'),
    );
    bool isWinnerValid = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Editar juego'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // SELECT de loterías
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: selLotteryId,
                  decoration: const InputDecoration(
                    labelText: 'Lotería',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: lots
                      .map(
                        (it) => DropdownMenuItem<int>(
                          value: it.id,
                          child: Text(it.name),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setLocal(() => selLotteryId = val),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event),
                        label: Text(
                          selDate == null
                              ? 'Elegir fecha'
                              : '${selDate!.year.toString().padLeft(4, '0')}-${selDate!.month.toString().padLeft(2, '0')}-${selDate!.day.toString().padLeft(2, '0')}',
                        ),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: selDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setLocal(() => selDate = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          selTime == null
                              ? 'Elegir hora'
                              : '${selTime!.hour.toString().padLeft(2, '0')}:${selTime!.minute.toString().padLeft(2, '0')}',
                        ),
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: selTime ?? TimeOfDay.now(),
                          );
                          if (t != null) setLocal(() => selTime = t);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 👇 Campo de ganador DINÁMICO: 3 o 4 dígitos
                TextFormField(
                  controller: winnerCtrl,
                  decoration: InputDecoration(
                    labelText:
                        'Número ganador (exactamente $digits dígitos)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                    errorText: isWinnerValid
                        ? null
                        : 'Debe tener exactamente $digits dígitos',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(digits),
                  ],
                  onChanged: (v) {
                    final ok = v.isEmpty || v.length == digits;
                    setLocal(() {
                      isWinnerValid = ok;
                      if (v.isEmpty) {
                        selWinning = null;
                      } else if (v.length == digits) {
                        selWinning = int.tryParse(v);
                      } else {
                        selWinning = null;
                      }
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final txt = winnerCtrl.text.trim();
                  final okLen = txt.isEmpty || txt.length == digits;

                  if (!okLen) {
                    setLocal(() => isWinnerValid = false);
                    return;
                  }

                  if (txt.isEmpty) {
                    selWinning = null;
                  } else {
                    selWinning = int.tryParse(txt);
                  }

                  Navigator.pop(ctx, true);
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );

    final d = selDate;
    final t = selTime;

    if (ok != true || !mounted) return;
    final String? newDate = (d == null)
        ? null
        : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final String? newTime = (t == null)
        ? null
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final payload = GameEdit(
      lotteryId: selLotteryId,
      playedDate: newDate ?? (g.playedDate.isEmpty ? null : g.playedDate),
      playedTime: newTime ?? (g.playedTime.isEmpty ? null : g.playedTime),
      // si usas onSetWinner, aquí NO mandamos el ganador
      winningNumber: (widget.onSetWinner == null) ? selWinning : null,
    );

    final bool winnerChanged =
        selWinning != g.winningNumber && selWinning != null;

    try {
      setState(() => _savingId = g.id);

      GameRow updated = g.copyWith(
        lotteryName: (selLotteryId == null)
            ? g.lotteryName
            : (lots
                    .firstWhere(
                      (it) => it.id == selLotteryId,
                      orElse: () => const LotteryItem(id: -1, name: ''),
                    )
                    .name),
        playedDate: payload.playedDate ?? g.playedDate,
        playedTime: payload.playedTime ?? g.playedTime,
      );

      if (widget.onUpdate != null) {
        final fromApi = await widget.onUpdate!(g.id, payload);
        if (fromApi != null) {
          updated = fromApi;
        }
      }

      if (winnerChanged && widget.onSetWinner != null) {
        try {
          final fromWinner = await widget.onSetWinner!(g.id, selWinning!);
          if (fromWinner != null) {
            updated = fromWinner;
          } else {
            updated = updated.copyWith(winningNumber: selWinning);
          }
        } catch (e) {
          if (mounted) {
            await custom.AppDialogs.error(
              context: context,
              title: 'Error',
              message: 'No se pudo fijar el número ganador: $e',
            );
          }
          if (mounted) setState(() => _savingId = null);
          return;
        }
      }

      setState(() {
        final idx = _all.indexWhere((x) => x.id == g.id);
        if (idx != -1) _all[idx] = updated;
        _savingId = null;
      });

      if (!mounted) return;
      await custom.AppDialogs.success(
        context: context,
        title: 'Actualizado',
        message: 'El juego #${g.id} fue actualizado.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingId = null);
      await custom.AppDialogs.error(
        context: context,
        title: 'Error',
        message: 'No se pudo actualizar: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? _all
        : _all.where((g) {
            final q = _q.toLowerCase();
            return g.lotteryName.toLowerCase().contains(q) ||
                '${g.id}'.contains(q) ||
                g.playedDate.contains(_q) ||
                g.playedTime.contains(_q) ||
                (g.winningNumber != null &&
                    '${g.winningNumber}'.contains(_q));
          }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Juegos (${widget.countLoader != null ? _dbTotal : filtered.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refrescar',
                    icon: const Icon(Icons.refresh),
                    onPressed: _refresh,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: (_) => _refresh(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('Sin juegos'))
                      : ListView.builder(
                          controller: controller,
                          padding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final g = filtered[i];
                            final locked = _isLocked(g);
                            return Card(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: ListTile(
                                  isThreeLine: true,
                                  contentPadding:
                                      const EdgeInsets.only(right: 4),
                                  leading: const Icon(Icons.casino),
                                  title: Text(
                                    'Juego #${g.id}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(
                                              text: 'Lotería: ',
                                              style: TextStyle(
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(
                                                text: g.lotteryName),
                                          ],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(
                                              text: 'Tipo: ',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600),
                                            ),
                                            TextSpan(
                                              text: g.digits == 4
                                                  ? '4 cifras'
                                                  : '3 cifras',
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(
                                              text: 'Jugadores: ',
                                              style: TextStyle(
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(
                                                text:
                                                    '${g.playersCount}'),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 2,
                                        children: [
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                const TextSpan(
                                                  text: 'Fecha: ',
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: (g.playedDate
                                                          .isEmpty
                                                      ? '—'
                                                      : g.playedDate),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                const TextSpan(
                                                  text: 'Hora: ',
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: (g.playedTime
                                                          .isEmpty
                                                      ? '—'
                                                      : g.playedTime),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(
                                              text: 'Número ganador: ',
                                              style: TextStyle(
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(
                                              text: g.winningNumber ==
                                                      null
                                                  ? '—'
                                                  : g.winningNumber!
                                                      .toString()
                                                      .padLeft(
                                                          g.digits, '0'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: locked
                                              ? 'Edición bloqueada'
                                              : 'Editar juego',
                                          icon: (_savingId == g.id)
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : Icon(locked
                                                  ? Icons.lock
                                                  : Icons.edit),
                                          color: locked
                                              ? Colors.grey
                                              : Colors.deepPurple,
                                          onPressed: (_savingId == g.id ||
                                                  locked)
                                              ? null
                                              : () => _openEdit(g),
                                        ),
                                        IconButton(
                                          tooltip: 'Eliminar juego',
                                          icon: (_deletingId == g.id)
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(Icons.delete),
                                          color: Colors.red,
                                          onPressed:
                                              (widget.onDelete == null ||
                                                      _deletingId == g.id)
                                                  ? null
                                                  : () => _confirmDelete(g),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameRow {
  final int id;
  final String lotteryName;
  final String playedDate;
  final String playedTime;
  final int playersCount;
  final int? winningNumber;
  final int? stateId;

  /// 3 o 4 cifras
  final int digits;

  const GameRow({
    required this.id,
    required this.lotteryName,
    required this.playedDate,
    required this.playedTime,
    required this.playersCount,
    required this.digits,
    this.winningNumber,
    this.stateId,
  });

  GameRow copyWith({
    int? id,
    String? lotteryName,
    String? playedDate,
    String? playedTime,
    int? playersCount,
    int? winningNumber,
    int? stateId,
    int? digits,
  }) {
    return GameRow(
      id: id ?? this.id,
      lotteryName: lotteryName ?? this.lotteryName,
      playedDate: playedDate ?? this.playedDate,
      playedTime: playedTime ?? this.playedTime,
      playersCount: playersCount ?? this.playersCount,
      winningNumber: winningNumber ?? this.winningNumber,
      stateId: stateId ?? this.stateId,
      digits: digits ?? this.digits,
    );
  }
}

/// Catálogo de loterías para el select
class LotteryItem {
  final int id;
  final String name;
  const LotteryItem({required this.id, required this.name});
}

class GameEdit {
  final int? lotteryId;
  final String? playedDate;
  final String? playedTime;
  final int? winningNumber;

  GameEdit({
    this.lotteryId,
    this.playedDate,
    this.playedTime,
    this.winningNumber,
  });

  Map<String, dynamic> toJson() => {
        "lottery_id": lotteryId,
        "played_date": playedDate,
        "played_time": playedTime,
        "winning_number": winningNumber,
      };
}
