import 'package:flutter/material.dart';
import 'package:base_app/core/ui/dialogs.dart'
    as custom; // 👈 usa tus diálogos bonitos
import 'dart:async';

class UsersBottomSheet extends StatefulWidget {
  /// Carga la lista de usuarios.
  final Future<List<UserRow>> Function() loader;
/// Activa/renueva PRO manualmente indicando el product_id (cm_suscripcion / cml_suscripcion).
final Future<Map<String, dynamic>> Function(int userId, String productId)? onManualGrantPro;


  /// Actualiza el rol del usuario en backend. Debe devolver el usuario actualizado.
  /// Si por ahora tu backend solo devuelve {ok:true}, igual funcionará (fallback local).
  final Future<UserRow?> Function(int userId, int newRoleId) onUpdateRole;

  /// Elimina el usuario en backend.
  final Future<void> Function(int userId) onDelete;

  /// Catálogo de roles (id + nombre) para el dropdown.
  final List<RoleItem> roles;

  const UsersBottomSheet({
    super.key,
    required this.loader,
    required this.onUpdateRole,
    required this.onDelete,
    this.roles = const [
      RoleItem(id: 1, name: 'Administrador'),
      RoleItem(id: 2, name: 'Usuario'),
    ],
    this.onManualGrantPro, // 👈 agrega esta línea
  });


  @override
  State<UsersBottomSheet> createState() => _UsersBottomSheetState();
}

class _UsersBottomSheetState extends State<UsersBottomSheet> {
  List<UserRow> _all = [];
  String _q = '';
  bool _loading = true;

  int? _editingUserId; // id del usuario en edición (null si ninguno)
  int? _tempRoleId; // rol seleccionado temporalmente
  bool _saving = false; // evita taps dobles durante guardado
  int? _deletingId;
  String _prettyError(Object e) {
    final s = e.toString();
    final cleaned = s.startsWith('Exception: ') ? s.substring(11) : s;
    return cleaned.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
  }
Future<String?> _pickPlanDialog(BuildContext context, UserRow u) async {
  // Devuelve "cm_suscripcion", "cml_suscripcion" o null si cancela
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return SimpleDialog(
        title: Text('Elegir plan para ${u.name}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('cm_suscripcion'),
            child: const Text('PRO Completa · 60.000 COP'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('cml_suscripcion'),
            child: const Text('PRO Lite · 20.000 COP'),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancelar'),
          ),
        ],
      );
    },
  );
}

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _editingUserId = null; // salir de edición si refrescamos
      _tempRoleId = null;
      _saving = false;
    });
    final data = await widget.loader();
    setState(() {
      _all = data;
      _loading = false;
    });
  }

  void _startEdit(UserRow u) {
    setState(() {
      _editingUserId = u.id;
      _tempRoleId = u.roleId;
      _saving = false;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingUserId = null;
      _tempRoleId = null;
      _saving = false;
    });
  }

  Future<void> _saveEdit(UserRow u) async {
    if (_tempRoleId == null || _tempRoleId == u.roleId) return;
    setState(() => _saving = true);

    try {
      // 1) Actualizar en backend
      await widget.onUpdateRole(u.id, _tempRoleId!);

      // 2) Salir de edición y recargar desde backend
      _editingUserId = null;
      _tempRoleId = null;
      _saving = false;
      await _refresh();

      if (!mounted) return;

      // 3) Dialog de éxito (custom)
      await custom.AppDialogs.success(
        context: context,
        title: 'Actualizado',
        message: 'El rol de "${u.name}" se actualizó correctamente.',
        okText: 'Aceptar',
      );
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;

      await custom.AppDialogs.error(
        context: context,
        title: 'No se pudo actualizar',
        message: _prettyError(e),
        okText: 'Cerrar',
      );
    }
  }

  Future<void> _confirmDelete(UserRow u) async {
    final ok = await custom.AppDialogs.confirm(
      context: context,
      title: 'Eliminar usuario',
      message:
          '¿Deseas eliminar a "${u.name}"? Esta acción no se puede deshacer.',
      okText: 'Sí, eliminar',
      cancelText: 'Cancelar',
      destructive: true,
      icon: Icons.delete_forever,
    );

    if (!mounted || ok != true) return;

    try {
      setState(() => _deletingId = u.id);
      await widget.onDelete(u.id).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {
        _all.removeWhere((x) => x.id == u.id);
        _deletingId = null;
      });

      await custom.AppDialogs.success(
        context: context,
        title: 'Eliminado',
        message: 'El usuario fue eliminado correctamente.',
        okText: 'Aceptar',
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _deletingId = null);
      await custom.AppDialogs.error(
        context: context,
        title: 'Sin respuesta',
        message: 'El servidor tardó demasiado al eliminar. Intenta de nuevo.',
        okText: 'Cerrar',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      await custom.AppDialogs.error(
        context: context,
        title: 'No se puede eliminar',
        message: _prettyError(e),
        okText: 'Cerrar',
      );
    }
  }
Future<void> _grantPro(UserRow u) async {
  // 🔒 Blindaje: solo bloquear si REALMENTE tiene PRO activa
  if (_hasActivePro(u)) {
    await custom.AppDialogs.error(
      context: context,
      title: 'Ya tiene suscripción activa',
      message:
          'El usuario "${u.name}" ya cuenta con una suscripción PRO activa.',
      okText: 'Cerrar',
    );
    return;
  }

  if (widget.onManualGrantPro == null) return;

  // 1) Escoger plan
  final productId = await _pickPlanDialog(context, u);
  if (!mounted || productId == null) return; // canceló

  final planLabel = productId == 'cm_suscripcion'
      ? 'PRO Completa (60.000)'
      : 'PRO Lite (20.000)';

  // 2) Confirmar
  final ok = await custom.AppDialogs.confirm(
    context: context,
    title: 'Activar PRO',
    message:
        '¿Quieres activar o renovar $planLabel por 30 días para "${u.name}"?\n\n'
        'Solo debe usarse cuando el usuario pagó por fuera de Play Store.',
    okText: 'Sí, activar',
    cancelText: 'Cancelar',
    destructive: false,
    icon: Icons.star,
  );

  if (ok != true || !mounted) return;

  try {
    final resp = await widget.onManualGrantPro!(u.id, productId);

    if (!mounted) return;

    final expiresAt = (resp['expiresAt'] as String?) ?? '';

    await custom.AppDialogs.success(
      context: context,
      title: 'PRO activado',
      message: expiresAt.isEmpty
          ? 'La suscripción $planLabel se activó/renovó correctamente.'
          : 'La suscripción $planLabel de "${u.name}" está activa hasta:\n$expiresAt',
      okText: 'Aceptar',
    );

    await _refresh();
  } catch (e) {
    if (!mounted) return;
    await custom.AppDialogs.error(
      context: context,
      title: 'No se pudo activar PRO',
      message: _prettyError(e),
      okText: 'Cerrar',
    );
  }
}

Future<void> _showManualProDialog(BuildContext context, UserRow u) async {
  final ok = await custom.AppDialogs.confirm(
    context: context,
    title: 'Activar PRO manual',
    message:
        '¿Deseas activar PRO por 30 días para "${u.name}"?\n\n'
        'Solo debe usarse cuando el usuario pagó por fuera de Play Store.',
    okText: 'Activar',
    cancelText: 'Cancelar',
    destructive: false,
    icon: Icons.workspace_premium,
  );

  if (ok != true) return;

  await _activatePro(u);
}

Future<void> _activatePro(UserRow u) async {
  try {
    // Llamada a tu backend (por ahora SIN endpoint real)
    // Aquí enviamos: userId y 30 días
    await widget.onUpdateRole(
      u.id,
      u.roleId, // no cambia rol, pero lo usamos como transporte
    );

    // ❗ REFRESCA LA LISTA COMPLETA
    await _refresh();

    if (!mounted) return;

    await custom.AppDialogs.success(
      context: context,
      title: 'PRO activado',
      message: 'La suscripción de "${u.name}" fue activada por 30 días.',
      okText: 'Aceptar',
    );
  } catch (e) {
    if (!mounted) return;

    await custom.AppDialogs.error(
      context: context,
      title: 'Error',
      message: _prettyError(e),
      okText: 'Cerrar',
    );
  }
}

  String _subLabel(UserRow u) {
    final s = (u.subscription ?? '').trim();

    // Si el backend ya manda una etiqueta (p.ej. "PRO (vence 2025-09-29)" o "FREE")
    // úsala tal cual, excepto cuando viene "-" que significa "sin suscripción".
    if (s.isNotEmpty && s != '-') return s;

    // Si no hay etiqueta, decide por entitlement
    final ent = (u.subscriptionEntitlement ?? '').trim().toLowerCase();
    if (ent == 'pro') return 'PRO';

    // ⭐ Texto para quienes no tienen suscripción
    return 'GRATIS'; // o 'Sin suscripción' si lo prefieres
  }
  String _statusLabelEs(UserRow u) {
  final raw = (u.subscriptionStatus ?? '').toLowerCase();

  switch (raw) {
    case 'active':
      return 'Activa';
    case 'canceled':
      return 'Cancelada (vigente)';
    case 'expired':
      return 'Vencida';
    case 'grace':
      return 'En período de gracia';
    case 'on_hold':
      return 'En retención';
    case 'paused':
      return 'Pausada';
    case 'revoked':
      return 'Revocada';
    case 'none':
    case '':
      return 'Sin suscripción';
    default:
      // Por si llega algo raro, mostramos el valor crudo
      return u.subscriptionStatus ?? raw;
  }
}

bool _hasActivePro(UserRow u) {
  final status = (u.subscriptionStatus ?? '').toLowerCase();

  // Solo consideramos "PRO activa" cuando el estado es ACTIVE.
  // El backend ya marca EXPPIRED, CANCELED, etc.
  return status == 'active';
}


  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? _all
        : _all
              .where(
                (u) =>
                    u.name.toLowerCase().contains(_q.toLowerCase()) ||
                    u.phone.contains(_q) ||
                    u.code.toLowerCase().contains(_q.toLowerCase()) ||
                    u.role.toLowerCase().contains(_q.toLowerCase()),
              )
              .toList();

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
                    'Usuarios',
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
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? const Center(child: Text('Sin usuarios'))
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final u = filtered[i];
                        final isEditing = _editingUserId == u.id;
final rawStatus = (u.subscriptionStatus ?? '');
final showStatus =
    rawStatus.isNotEmpty && rawStatus.toLowerCase() != 'none';
final showExpires =
    (u.subscriptionExpiresAt ?? '').isNotEmpty;

                        final hasActivePro = _hasActivePro(u);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ListTile(
                              isThreeLine: true,
                              contentPadding: const EdgeInsets.only(right: 4),
                              leading: const Icon(Icons.person),
                              title: Text(
                                u.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('📞 ${u.phone}'),
                                  const SizedBox(height: 2),

                                  // Rol (edición / lectura)
                                  if (isEditing)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          const Text(
                                            'Rol:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          DropdownButton<int>(
                                            isDense: true,
                                            underline: const SizedBox.shrink(),
                                            hint: const Text(
                                              'Selecciona un rol',
                                            ),
                                            value:
                                                widget.roles.any(
                                                  (r) => r.id == _tempRoleId,
                                                )
                                                ? _tempRoleId
                                                : null,
                                            items: widget.roles
                                                .map(
                                                  (r) => DropdownMenuItem<int>(
                                                    value: r.id,
                                                    child: Text(r.name),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: _saving
                                                ? null
                                                : (val) => setState(
                                                    () => _tempRoleId = val,
                                                  ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Text(
                                      'Rol: ${(widget.roles.firstWhere(
                                        (r) => r.id == u.roleId,
                                        orElse: () => RoleItem(id: u.roleId, name: u.role.isEmpty ? 'Usuario' : u.role),
                                      ).name)}',
                                    ),

                                  const SizedBox(height: 2),
                                  Text('Suscripción: ${_subLabel(u)}'),
                                  if (showStatus) Text('Estado: ${_statusLabelEs(u)}'),
                                  if (showExpires)
                                    Text('Vence: ${u.subscriptionExpiresAt}'),

                                  const SizedBox(height: 2),
                                  Text('Código: ${u.code}'),
                                ],
                              ),

trailing: FittedBox(
  fit: BoxFit.scaleDown,
  child: isEditing
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Cancelar',
              icon: const Icon(Icons.close),
              color: Colors.red[700],
              onPressed: _saving ? null : _cancelEdit,
            ),
            IconButton(
              tooltip: 'Guardar',
              icon: const Icon(Icons.check),
              color: Colors.deepPurple,
              onPressed:
                  _saving || _tempRoleId == u.roleId ? null : () => _saveEdit(u),
            ),
          ],
        )
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⭐ Botón PRO, solo si NO tiene PRO activa
            if (!hasActivePro)
              IconButton(
                tooltip: 'Activar PRO 30 días',
                icon: const Icon(Icons.star),
                color: Colors.amber[700],
                onPressed: widget.onManualGrantPro == null
                    ? null
                    : () => _grantPro(u),
              ),

            IconButton(
              tooltip: 'Editar rol',
              icon: const Icon(Icons.edit),
              color: Colors.deepPurple,
              onPressed: () => _startEdit(u),
            ),
            IconButton(
              tooltip: 'Eliminar usuario',
              icon: (_deletingId == u.id)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete),
              color: Colors.red,
              onPressed:
                  (_deletingId == u.id) ? null : () => _confirmDelete(u),
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

class UserRow {
  final int id;
  final String name;
  final String phone;
  final String code;
  final int roleId;
  final String role;

  // 👇 nuevos (todos opcionales, vienen directo del backend)
  final String? subscription; // etiqueta que envía el backend (PRO/FREE o null)
  final String? subscriptionStatus; // p.ej. ACTIVE/CANCELED/GRACE…
  final String? subscriptionEntitlement; // p.ej. "pro"
  final String? subscriptionExpiresAt; // ISO string si viene

  const UserRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.code,
    required this.roleId,
    required this.role,
    this.subscription,
    this.subscriptionStatus,
    this.subscriptionEntitlement,
    this.subscriptionExpiresAt,
  });

  factory UserRow.fromJson(Map<String, dynamic> j) {
    return UserRow(
      id: (j['id'] as num).toInt(),
      name: (j['name'] ?? '') as String,
      phone: (j['phone'] ?? '') as String,
      code: (j['public_code'] ?? j['code'] ?? '') as String,
      roleId: (j['role_id'] as num?)?.toInt() ?? 2,
      role: (j['role'] ?? 'Usuario') as String,

      // 👇 vienen directo del backend Python
      subscription: j['subscription'] as String?,
      subscriptionStatus: j['subscription_status'] as String?,
      subscriptionEntitlement: (j['subscription_entitlement'] as String?)
          ?.toLowerCase(),
      subscriptionExpiresAt: j['subscription_expires_at'] as String?,
    );
  }

  UserRow copyWith({
    int? id,
    String? name,
    String? phone,
    String? code,
    int? roleId,
    String? role,
    String? subscription,
    String? subscriptionStatus,
    String? subscriptionEntitlement,
    String? subscriptionExpiresAt,
  }) {
    return UserRow(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      code: code ?? this.code,
      roleId: roleId ?? this.roleId,
      role: role ?? this.role,
      subscription: subscription ?? this.subscription,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionEntitlement:
          subscriptionEntitlement ?? this.subscriptionEntitlement,
      subscriptionExpiresAt:
          subscriptionExpiresAt ?? this.subscriptionExpiresAt,
    );
  }
}

class RoleItem {
  final int id;
  final String name;
  const RoleItem({required this.id, required this.name});
}
