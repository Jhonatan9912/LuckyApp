// lib/web/admin/admin_users_page.dart
import 'package:flutter/material.dart';

import 'package:base_app/core/ui/dialogs.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/admin_dashboard_controller.dart';
import 'package:base_app/presentation/screens/admin_dashboard/widgets/users_bottom_sheet.dart'
    show UserRow;

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/web_ui.dart';
import 'admin_common.dart';

const _plans = [
  ('cm_prueba_2', 'Prueba gratuita · 2 cifras', '1 mes gratis', true),
  ('cm_prueba_3', 'Prueba gratuita · 3 cifras', '1 mes gratis', true),
  ('cm_prueba_4', 'Prueba gratuita · 4 cifras', '1 mes gratis', true),
  ('cm_prueba_5', 'Prueba gratuita · Quinta', '1 mes gratis', true),
  ('cms_suscripcion', 'Starter · 2 cifras', r'$10.000 COP', false),
  ('cml_suscripcion', 'Lite · 3 cifras', r'$20.000 COP', false),
  ('cm_suscripcion', 'Completa · 4 cifras', r'$60.000 COP', false),
  ('cmu_suscripcion', 'Quinta · 5 cifras', r'$100.000 COP', false),
];

enum _UserFilter { all, pro, free, admins }

class AdminUsersPage extends StatefulWidget {
  final AdminDashboardController ctrl;
  const AdminUsersPage({super.key, required this.ctrl});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _search = TextEditingController();
  List<UserRow> _all = [];
  bool _loading = true;
  String? _error;
  int? _busyId;
  _UserFilter _filter = _UserFilter.all;

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
      final list = await widget.ctrl.loadAllUsers();
      if (!mounted) return;
      setState(() => _all = list.map(UserRow.fromJson).toList());
    } catch (e) {
      if (mounted) setState(() => _error = prettyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isActive(UserRow u) =>
      (u.subscriptionStatus ?? '').toLowerCase() == 'active';

  String _statusEs(UserRow u) =>
      switch ((u.subscriptionStatus ?? '').toLowerCase()) {
        'active' => 'Activa',
        'canceled' => 'Cancelada (vigente)',
        'expired' => 'Vencida',
        'grace' => 'En gracia',
        'on_hold' => 'En retención',
        'paused' => 'Pausada',
        'revoked' => 'Revocada',
        '' || 'none' => 'Sin plan',
        final s => s,
      };

  String _planLabel(UserRow u) {
    final s = (u.subscription ?? '').trim();
    if (s.isNotEmpty && s != '-') return s;
    return (u.subscriptionEntitlement ?? '') == 'pro' ? 'PRO' : 'Gratis';
  }

  List<UserRow> get _rows {
    final q = _search.text.trim().toLowerCase();
    return _all.where((u) {
      final okFilter = switch (_filter) {
        _UserFilter.all => true,
        _UserFilter.pro => _isActive(u),
        _UserFilter.free => !_isActive(u),
        _UserFilter.admins => u.roleId == 1,
      };
      if (!okFilter) return false;
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.phone.contains(q) ||
          u.code.toLowerCase().contains(q) ||
          u.role.toLowerCase().contains(q);
    }).toList();
  }

  // ───────────── Acciones ─────────────

  Future<void> _changeRole(UserRow u) async {
    final newRole = u.roleId == 1 ? 2 : 1;
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: newRole == 1
          ? 'Convertir en administrador'
          : 'Quitar administrador',
      message: newRole == 1
          ? '"${u.name}" podrá entrar al panel de administración.'
          : '"${u.name}" pasará a ser un usuario normal.',
      okText: 'Confirmar',
      icon: Icons.admin_panel_settings_outlined,
    );
    if (!ok) return;
    setState(() => _busyId = u.id);
    try {
      await widget.ctrl.updateUserRole(u.id, newRole);
      WebAlerts.toast(
        'El rol de "${u.name}" se actualizó.',
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

  Future<void> _grantPlan(UserRow u) async {
    if (_isActive(u)) {
      await WebAlerts.dialog(
        title: 'Ya tiene un plan activo',
        message: '"${u.name}" ya cuenta con una suscripción activa.',
        tone: AlertTone.warning,
      );
      return;
    }

    String? selected;
    final productId = await showWebModal<String>(
      context,
      title: 'Activar plan',
      subtitle: 'Para ${u.name} · 30 días',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (id, name, price, trial) in _plans)
              ChoiceTile(
                title: name,
                subtitle: price,
                icon: trial
                    ? Icons.card_giftcard_rounded
                    : Icons.workspace_premium_rounded,
                selected: selected == id,
                onTap: () => setLocal(() => selected = id),
              ),
            Text(
              'Usa los planes pagados solo cuando el usuario pagó por fuera de Google Play.',
              style: WebPalette.body(12.5, color: WebPalette.textFaint),
            ),
            ModalActions(
              okText: 'Activar plan',
              onOk: selected == null
                  ? null
                  : () => Navigator.of(ctx).pop(selected),
            ),
          ],
        ),
      ),
    );
    if (productId == null) return;

    final label = _plans.firstWhere((p) => p.$1 == productId).$2;
    setState(() => _busyId = u.id);
    try {
      final resp = await widget.ctrl.manualGrantPro(
        userId: u.id,
        productId: productId,
        days: 30,
      );
      final expRaw = (resp['expiresAt'] as String?) ?? '';
      final expDt = DateTime.tryParse(expRaw)?.toLocal();
      final exp = expDt == null
          ? expRaw
          : '${expDt.day.toString().padLeft(2, '0')}/${expDt.month.toString().padLeft(2, '0')}/${expDt.year}';
      WebAlerts.toast(
        exp.isEmpty
            ? '$label activado para "${u.name}".'
            : '$label activo hasta $exp.',
        title: 'Plan activado',
        tone: AlertTone.success,
      );
      await _load();
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo activar',
        message: prettyError(e),
        tone: AlertTone.error,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(UserRow u) async {
    final ok = await AppDialogs.confirmPlain(
      context: context,
      title: 'Eliminar usuario',
      message:
          '¿Deseas eliminar a "${u.name}"? Esta acción no se puede deshacer.',
      okText: 'Sí, eliminar',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok) return;
    setState(() => _busyId = u.id);
    try {
      await widget.ctrl.deleteUser(u.id).timeout(const Duration(seconds: 15));
      setState(() => _all.removeWhere((x) => x.id == u.id));
      WebAlerts.toast('Usuario eliminado.', tone: AlertTone.success);
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se puede eliminar',
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
    final pro = _all.where(_isActive).length;
    final admins = _all.where((u) => u.roleId == 1).length;

    return WebPage(
      children: [
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            StatTile(
              label: 'Usuarios registrados',
              value: '${_all.length}',
              icon: Icons.people_alt_outlined,
            ),
            StatTile(
              label: 'Con plan activo',
              value: '$pro',
              icon: Icons.workspace_premium_outlined,
              color: WebPalette.emerald,
            ),
            StatTile(
              label: 'Sin plan',
              value: '${_all.length - pro}',
              icon: Icons.person_outline_rounded,
              color: WebPalette.textMuted,
            ),
            StatTile(
              label: 'Administradores',
              value: '$admins',
              icon: Icons.admin_panel_settings_outlined,
              color: WebPalette.violet,
            ),
          ],
        ),
        const SizedBox(height: 22),
        WebPanel(
          title: 'Usuarios',
          subtitle: '${rows.length} de ${_all.length} usuarios',
          icon: Icons.people_alt_outlined,
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
                hint: 'Buscar por nombre, celular o código',
                onSearch: (_) => setState(() {}),
                filters: [
                  WebSegmented<_UserFilter>(
                    options: const [
                      (_UserFilter.all, 'Todos'),
                      (_UserFilter.pro, 'Con plan'),
                      (_UserFilter.free, 'Sin plan'),
                      (_UserFilter.admins, 'Admins'),
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
                  title: 'Sin resultados',
                )
              else
                WebTable<UserRow>(
                  rows: rows,
                  mobileTitle: (u) => Text(
                    u.name,
                    style: WebPalette.display(15, weight: FontWeight.w700),
                  ),
                  trailing: (u) => RowActions(
                    busy: _busyId == u.id,
                    actions: [
                      RowAction(
                        Icons.workspace_premium_outlined,
                        'Activar plan',
                        () => _grantPlan(u),
                      ),
                      RowAction(
                        Icons.admin_panel_settings_outlined,
                        u.roleId == 1
                            ? 'Quitar administrador'
                            : 'Hacer administrador',
                        () => _changeRole(u),
                      ),
                      RowAction(
                        Icons.delete_outline_rounded,
                        'Eliminar',
                        () => _delete(u),
                        danger: true,
                      ),
                    ],
                  ),
                  columns: [
                    WebColumn(
                      'Nombre',
                      (u) => CellText(u.name, strong: true),
                      flex: 3,
                    ),
                    WebColumn('Celular', (u) => CellText(u.phone), flex: 2),
                    WebColumn(
                      'Código',
                      (u) => CellText(u.code, mono: true),
                      flex: 2,
                    ),
                    WebColumn(
                      'Rol',
                      (u) => u.roleId == 1
                          ? const StatusChip(
                              label: 'Admin',
                              color: WebPalette.violet,
                            )
                          : const StatusChip(
                              label: 'Usuario',
                              color: WebPalette.textMuted,
                            ),
                      flex: 2,
                    ),
                    WebColumn('Plan', (u) => CellText(_planLabel(u)), flex: 2),
                    WebColumn(
                      'Estado',
                      (u) => StatusChip(
                        label: _statusEs(u),
                        color: _isActive(u)
                            ? WebPalette.emerald
                            : WebPalette.textFaint,
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
