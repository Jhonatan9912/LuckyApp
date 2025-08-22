import 'package:flutter/material.dart';
import 'package:base_app/core/ui/dialogs.dart'
    as custom; // 👈 usa tus diálogos bonitos
import 'dart:async';

class UsersBottomSheet extends StatefulWidget {
  /// Carga la lista de usuarios.
  final Future<List<UserRow>> Function() loader;

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
                                  // Rol (en edición -> dropdown; normal -> texto)
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
                                            'Rol: ',
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
                                  Text('Código: ${u.code}'),
                                ],
                              ),
                              // Acciones
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
                                            onPressed: _saving
                                                ? null
                                                : _cancelEdit,
                                          ),
                                          IconButton(
                                            tooltip: 'Guardar',
                                            icon: const Icon(Icons.check),
                                            color: Colors.deepPurple,
                                            onPressed:
                                                _saving ||
                                                    _tempRoleId == u.roleId
                                                ? null
                                                : () => _saveEdit(u),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
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
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Icon(Icons.delete),
                                            color: Colors.red,
                                            onPressed: (_deletingId == u.id)
                                                ? null
                                                : () => _confirmDelete(u),
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

  const UserRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.code,
    required this.roleId,
    required this.role,
  });

  UserRow copyWith({
    int? id,
    String? name,
    String? phone,
    String? code,
    int? roleId,
    String? role,
  }) {
    return UserRow(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      code: code ?? this.code,
      roleId: roleId ?? this.roleId,
      role: role ?? this.role,
    );
  }
}

class RoleItem {
  final int id;
  final String name;
  const RoleItem({required this.id, required this.name});
}
