import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:base_app/core/ui/dialogs.dart' as custom;

/// BottomSheet de Jugadores (estructura similar a Users/Games).
class PlayersBottomSheet extends StatefulWidget {
  /// Carga la lista de jugadores (estructura libre).
  final Future<List<PlayerRow>> Function({String q, String state}) loader;

  /// Devuelve el total en DB (opcional).
  final Future<int> Function({String q, String state})? countLoader;

  /// Elimina TODAS las balotas del jugador en un juego.
  final Future<void> Function(int userId, int gameId)? onDelete;

  /// Abre detalle (opcional).
  final Future<PlayerRow?> Function(int playerId)? onOpen;

  /// Actualiza las balotas del jugador en un juego.
  final Future<List<String>> Function(
    int userId,
    int gameId,
    List<String> numbers,
  )? onUpdateNumbers;

  const PlayersBottomSheet({
    super.key,
    required this.loader,
    this.countLoader,
    this.onDelete,
    this.onOpen,
    this.onUpdateNumbers,
  });

  @override
  State<PlayersBottomSheet> createState() => _PlayersBottomSheetState();
}

class _PlayersBottomSheetState extends State<PlayersBottomSheet> {
  List<PlayerRow> _all = [];
  String _q = '';
  String _state = 'active'; // pestaña actual: active / historical
  bool _loading = true;
  int _dbTotal = 0;
  int? _workingId;
  DateTime _now = DateTime.now();
  Timer? _ticker;

  /// Filtro interno por dígitos (null = todos, 3 = solo 3 cifras, 4 = solo 4 cifras)
  int? _digitsFilter;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_refresh);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _workingId = null;
    });
    try {
      // pasa state al loader
      final data = await widget.loader(q: _q, state: _state);

      int total;
      if (widget.countLoader != null) {
        // pasa state al countLoader
        total = await widget.countLoader!(q: '', state: _state);
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
        message: 'No se pudo cargar la lista de jugadores.\n$e',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _prettyError(Object e) {
    final s = e.toString();
    final cleaned = s.startsWith('Exception: ') ? s.substring(11) : s;
    return cleaned.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
  }

  bool _isLocked(PlayerRow p) {
    try {
      final date = p.playedDate.trim(); // 'YYYY-MM-DD'
      final rawTime = p.playedTime.trim(); // 'HH:MM' o 'HH:MM:SS'
      final t = rawTime.replaceAll(RegExp(r'\s+'), '');
      final parts = t.split(':');
      final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      final s = int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0;

      final hh = h.toString().padLeft(2, '0');
      final mm = m.toString().padLeft(2, '0');
      final ss = s.toString().padLeft(2, '0');

      final gameDT = DateTime.parse('$date $hh:$mm:$ss');

      return !_now.isBefore(gameDT);
    } catch (_) {
      return false;
    }
  }

  Future<void> _editNumbers(PlayerRow p, int indexInList) async {
    if (widget.onUpdateNumbers == null) return;

    final formKey = GlobalKey<FormState>();
    final digits = p.digits; // 3 o 4
    final ctrls = p.numbers
        .map((n) => TextEditingController(
              text: n.toString().padLeft(digits, '0'),
            ))
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Editar balotas'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(ctrls.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: ctrls[i],
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(digits),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Balota ${i + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (val) {
                      final v = (val ?? '').trim();
                      if (v.isEmpty) return 'Requerido';
                      if (v.length != digits) {
                        return 'Debe tener $digits dígitos';
                      }
                      final reg = RegExp(r'^\d+$');
                      if (!reg.hasMatch(v)) return 'Sólo dígitos';
                      return null;
                    },
                  ),
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    final newNumbers = ctrls
        .map((c) => c.text.trim().padLeft(digits, '0'))
        .toList(growable: false);

    try {
      setState(() => _workingId = p.id);
      final returned = await widget.onUpdateNumbers!(
        p.id,
        p.gameId,
        newNumbers,
      );
      if (!mounted) return;
      setState(() {
        _all[indexInList] = _all[indexInList].copyWith(
          numbers: returned.isNotEmpty ? returned : newNumbers,
        );
        _workingId = null;
      });
      await custom.AppDialogs.success(
        context: context,
        title: 'Actualizado',
        message: 'Las balotas fueron actualizadas.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _workingId = null);
      final msg = _prettyError(e);
      await custom.AppDialogs.error(
        context: context,
        title: 'Error',
        message: msg,
      );
    }
  }

  Widget _buildDigitsFilterChips() {
    // Solo lo mostramos para la pestaña "Activos"
    if (_state != 'active') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          _buildDigitsChip(label: 'Todos', value: null),
          const SizedBox(width: 8),
          _buildDigitsChip(label: '3 cifras', value: 3),
          const SizedBox(width: 8),
          _buildDigitsChip(label: '4 cifras', value: 4),
        ],
      ),
    );
  }

  Widget _buildDigitsChip({required String label, required int? value}) {
    final selected = _digitsFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _digitsFilter = value;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filtro por texto
    List<PlayerRow> filtered = _q.isEmpty
        ? _all
        : _all.where((p) {
            final q = _q.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                p.id.toString().contains(_q) ||
                p.code.toLowerCase().contains(q) ||
                p.lotteryName.toLowerCase().contains(q) ||
                p.playedDate.contains(_q) ||
                p.playedTime.contains(_q) ||
                p.numbers.any((n) => n.toString().contains(_q));
          }).toList();

    // Filtro por dígitos (3 / 4) si está seleccionado
    if (_digitsFilter != null) {
      filtered =
          filtered.where((p) => p.digits == _digitsFilter).toList();
    }

    return DefaultTabController(
      // tabs Activos / Histórico
      length: 2,
      initialIndex: _state == 'active' ? 0 : 1,
      child: DraggableScrollableSheet(
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
                      'Jugadores (${widget.countLoader != null ? _dbTotal : filtered.length})',
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

              // TabBar principal: Activos / Histórico
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TabBar(
                  tabs: const [
                    Tab(text: 'Activos'),
                    Tab(text: 'Histórico'),
                  ],
                  onTap: (i) {
                    final next = (i == 0) ? 'active' : 'historical';
                    if (_state != next) {
                      setState(() {
                        _state = next;
                        // al cambiar de pestaña, quitamos filtro de dígitos
                        _digitsFilter = null;
                      });
                      _refresh(); // recarga con el nuevo estado
                    }
                  },
                ),
              ),

              // Filtro interno de 3 / 4 cifras solo para "Activos"
              _buildDigitsFilterChips(),
              const SizedBox(height: 4),

              // Buscador
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
                        ? const Center(child: Text('Sin jugadores'))
                        : ListView.builder(
                            controller: controller,
                            padding:
                                const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final p = filtered[i];
                              final locked = _isLocked(p);
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
                                    leading:
                                        const Icon(Icons.person_outline),
                                    title: Text(
                                      p.name,
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
                                                text: 'Jugador: ',
                                                style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                              TextSpan(text: p.name),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: 'Código: ',
                                                style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                              TextSpan(text: p.code),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: 'Juego asignado: ',
                                                style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                              TextSpan(
                                                text:
                                                    'Juego #${p.gameId} · ${p.lotteryName}',
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: 'Balotas: ',
                                                style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                              TextSpan(
                                                text: p.numbers
                                                    .map(
                                                      (n) =>
                                                          n.toString().padLeft(
                                                                p.digits,
                                                                '0',
                                                              ),
                                                    )
                                                    .join(', '),
                                              ),
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
                                                  TextSpan(text: p.playedDate),
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
                                                  TextSpan(text: p.playedTime),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (locked)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: Row(
                                              children: [
                                                Icon(Icons.lock_clock,
                                                    size: 16),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Edición bloqueada',
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
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
                                          // EDITAR
                                          Builder(
                                            builder: (ctx) {
                                              final canEdit =
                                                  widget.onUpdateNumbers !=
                                                          null &&
                                                      _workingId != p.id &&
                                                      !locked;
                                              return IconButton(
                                                tooltip: locked
                                                    ? 'Edición bloqueada: el juego ya inició'
                                                    : 'Editar',
                                                icon: (_workingId == p.id)
                                                    ? const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : Icon(locked
                                                        ? Icons.lock_clock
                                                        : Icons.edit),
                                                color: canEdit
                                                    ? Colors.deepPurple
                                                    : null,
                                                onPressed: !canEdit
                                                    ? null
                                                    : () => _editNumbers(
                                                          p,
                                                          i,
                                                        ),
                                              );
                                            },
                                          ),

                                          // ELIMINAR
                                          IconButton(
                                            tooltip: locked
                                                ? 'Bloqueado'
                                                : 'Eliminar',
                                            icon: (_workingId == p.id)
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
                                            onPressed: (_workingId == p.id ||
                                                    widget.onDelete == null ||
                                                    locked)
                                                ? null
                                                : () async {
                                                    final ctx = context;
                                                    final ok =
                                                        await custom
                                                            .AppDialogs
                                                            .confirm(
                                                      context: ctx,
                                                      title:
                                                          'Eliminar jugador',
                                                      message:
                                                          '¿Deseas eliminar las balotas de "${p.name}" para este juego?\n'
                                                          'Esto no elimina al usuario, solo sus números.',
                                                      okText: 'Sí, eliminar',
                                                      cancelText: 'Cancelar',
                                                      destructive: true,
                                                      icon: Icons
                                                          .delete_forever,
                                                    );
                                                    if (ok != true ||
                                                        !ctx.mounted) {
                                                      return;
                                                    }
                                                    setState(() =>
                                                        _workingId = p.id);
                                                    try {
                                                      await widget.onDelete!(
                                                        p.id,
                                                        p.gameId,
                                                      );
                                                      if (!ctx.mounted) {
                                                        return;
                                                      }
                                                      setState(() {
                                                        _all.removeAt(i);
                                                        _workingId = null;
                                                      });
                                                      await custom
                                                          .AppDialogs
                                                          .success(
                                                        context: ctx,
                                                        title: 'Eliminado',
                                                        message:
                                                            'Se eliminaron las balotas del jugador para este juego.',
                                                      );
                                                    } catch (e) {
                                                      if (!ctx.mounted) {
                                                        return;
                                                      }
                                                      setState(() =>
                                                          _workingId = null);
                                                      await custom
                                                          .AppDialogs
                                                          .error(
                                                        context: ctx,
                                                        title: 'Error',
                                                        message:
                                                            'No se pudo eliminar: $e',
                                                      );
                                                    }
                                                  },
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
      ),
    );
  }
}

class PlayerRow {
  final int id; // user_id
  final String name; // player_name
  final String code; // public_code
  final int gameId; // game_id
  final String lotteryName; // lottery_name
  final String playedDate; // 'YYYY-MM-DD'
  final String playedTime; // 'HH:MM'
  final List<String> numbers; // balotas (como strings)
  final int digits; // 3 o 4 según el juego

  const PlayerRow({
    required this.id,
    required this.name,
    required this.code,
    required this.gameId,
    required this.lotteryName,
    required this.playedDate,
    required this.playedTime,
    required this.numbers,
    this.digits = 3,
  });

  PlayerRow copyWith({
    int? id,
    String? name,
    String? code,
    int? gameId,
    String? lotteryName,
    String? playedDate,
    String? playedTime,
    List<String>? numbers,
    int? digits,
  }) {
    return PlayerRow(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      gameId: gameId ?? this.gameId,
      lotteryName: lotteryName ?? this.lotteryName,
      playedDate: playedDate ?? this.playedDate,
      playedTime: playedTime ?? this.playedTime,
      numbers: numbers ?? this.numbers,
      digits: digits ?? this.digits,
    );
  }
}
