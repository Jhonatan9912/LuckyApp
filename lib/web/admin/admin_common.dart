// lib/web/admin/admin_common.dart
import 'package:flutter/material.dart';

import '../theme/web_palette.dart';
import '../widgets/web_ui.dart';

/// Limpia mensajes de error del backend para mostrarlos.
String prettyError(Object e) {
  final s = e.toString();
  final cleaned = s.startsWith('Exception: ') ? s.substring(11) : s;
  return cleaned.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
}

/// Barra de herramientas de una tabla: buscador + filtros + acciones.
class TableToolbar extends StatelessWidget {
  final TextEditingController search;
  final String hint;
  final ValueChanged<String> onSearch;
  final List<Widget> filters;
  final List<Widget> actions;

  const TableToolbar({
    super.key,
    required this.search,
    required this.hint,
    required this.onSearch,
    this.filters = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: WebSearchField(
            controller: search,
            hint: hint,
            onChanged: onSearch,
            onSubmitted: onSearch,
          ),
        ),
        ...filters,
        ...actions,
      ],
    );
  }
}

/// Menú de acciones por fila (tres puntos).
class RowActions extends StatelessWidget {
  final List<RowAction> actions;
  final bool busy;
  const RowActions({super.key, required this.actions, this.busy = false});

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }
    return PopupMenuButton<int>(
      tooltip: 'Acciones',
      color: WebPalette.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: WebPalette.glassBorder),
      ),
      icon: const Icon(Icons.more_horiz_rounded, color: WebPalette.textMuted),
      onSelected: (i) => actions[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem(
            value: i,
            enabled: actions[i].enabled,
            child: Row(
              children: [
                Icon(
                  actions[i].icon,
                  size: 18,
                  color: actions[i].danger
                      ? WebPalette.danger
                      : WebPalette.goldLight,
                ),
                const SizedBox(width: 12),
                Text(
                  actions[i].label,
                  style: WebPalette.body(
                    14,
                    weight: FontWeight.w600,
                    color: actions[i].danger
                        ? WebPalette.danger
                        : WebPalette.text,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RowAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool enabled;
  const RowAction(
    this.icon,
    this.label,
    this.onTap, {
    this.danger = false,
    this.enabled = true,
  });
}

/// Botones de pie para formularios en modales.
class ModalActions extends StatelessWidget {
  final String okText;
  final VoidCallback? onOk;
  final bool loading;
  final bool danger;

  const ModalActions({
    super.key,
    required this.okText,
    required this.onOk,
    this.loading = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: loading ? null : () => Navigator.of(context).maybePop(),
            child: Text(
              'Cancelar',
              style: WebPalette.body(14, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger ? WebPalette.danger : WebPalette.gold,
              foregroundColor: danger ? Colors.white : const Color(0xFF1A1300),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: loading ? null : onOk,
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    okText,
                    style: WebPalette.body(
                      14,
                      weight: FontWeight.w800,
                      color: danger ? Colors.white : const Color(0xFF1A1300),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Opción seleccionable tipo tarjeta (para elegir planes, etc.).
class ChoiceTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const ChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? WebPalette.gold.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: selected
                ? WebPalette.gold.withValues(alpha: 0.6)
                : WebPalette.glassBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? WebPalette.goldLight : WebPalette.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: WebPalette.body(
                      14.5,
                      weight: FontWeight.w700,
                      color: WebPalette.text,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: WebPalette.body(12.5)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? WebPalette.goldLight : WebPalette.textFaint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
