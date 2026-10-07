// lib/web/widgets/web_ui.dart
//
// Componentes base del panel web: tarjetas, indicadores, chips de estado,
// buscador, segmentos, tabla adaptable y estados vacíos/carga.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/web_palette.dart';
import '../theme/web_theme.dart';
import 'lottery_ball.dart' show BallNumberText;

/// Formatea pesos colombianos: $ 1.234.567
String fmtCop(num v) =>
    '\$ ${NumberFormat.decimalPattern('es_CO').format(v.round())}';

/// Tamaños de pantalla.
class WebBreakpoints {
  static const double mobile = 720;
  static const double tablet = 1100;

  static bool isMobile(BuildContext c) => MediaQuery.sizeOf(c).width < mobile;
  static bool isDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= tablet;
}

/// Panel/tarjeta de contenido con encabezado opcional.
class WebPanel extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlight;

  const WebPanel({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlight
              ? [
                  WebPalette.gold.withValues(alpha: 0.14),
                  Colors.white.withValues(alpha: 0.03),
                ]
              : [
                  Colors.white.withValues(alpha: 0.055),
                  Colors.white.withValues(alpha: 0.025),
                ],
        ),
        border: Border.all(
          color: highlight
              ? WebPalette.gold.withValues(alpha: 0.35)
              : WebPalette.glassBorder,
        ),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: WebPalette.gold.withValues(alpha: 0.12),
                    ),
                    child: Icon(icon, size: 18, color: WebPalette.goldLight),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: WebPalette.display(17, weight: FontWeight.w700),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: WebPalette.body(13)),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 18),
          ],
          child,
        ],
      ),
    );
  }
}

/// Indicador numérico (KPI).
class StatTile extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = WebPalette.gold,
    this.hint,
    this.onTap,
  });

  @override
  State<StatTile> createState() => _StatTileState();
}

class _StatTileState extends State<StatTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final clickable = widget.onTap != null;
    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(
            0,
            _hover && clickable ? -3 : 0,
            0,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: _hover ? 0.07 : 0.045),
            border: Border.all(
              color: _hover && clickable
                  ? c.withValues(alpha: 0.5)
                  : WebPalette.glassBorder,
            ),
            boxShadow: [
              if (_hover && clickable)
                BoxShadow(color: c.withValues(alpha: 0.15), blurRadius: 30),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: c.withValues(alpha: 0.14),
                    ),
                    child: Icon(widget.icon, color: c, size: 20),
                  ),
                  const Spacer(),
                  if (clickable)
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: _hover ? c : WebPalette.textFaint,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.value,
                  style: WebPalette.display(28, weight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: WebPalette.body(
                  13.5,
                  weight: FontWeight.w600,
                  color: WebPalette.textMuted,
                ),
              ),
              if (widget.hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.hint!,
                  style: WebPalette.body(12, color: WebPalette.textFaint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rejilla adaptable para tarjetas (n columnas según ancho).
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Nunca más columnas que elementos, para que llenen todo el ancho.
        final cols = (c.maxWidth / (minItemWidth + spacing)).floor().clamp(
          1,
          children.isEmpty ? 1 : children.length.clamp(1, 6),
        );
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

/// Chip de estado con punto de color.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: WebPalette.body(
              12,
              weight: FontWeight.w700,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de búsqueda.
class WebSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  const WebSearchField({
    super.key,
    required this.controller,
    this.hint = 'Buscar…',
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: WebPalette.body(14, color: WebPalette.text),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      controller.clear();
                      onSubmitted?.call('');
                      onChanged?.call('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Selector segmentado (pestañas tipo píldora).
class WebSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Set<T> locked;

  const WebSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.locked = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: WebPalette.glassBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, label) in options)
              _SegButton(
                label: label,
                selected: v == value,
                locked: locked.contains(v),
                onTap: () => onChanged(v),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegButton extends StatefulWidget {
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  const _SegButton({
    required this.label,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  State<_SegButton> createState() => _SegButtonState();
}

class _SegButtonState extends State<_SegButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: sel ? WebPalette.goldGradient : null,
            color: sel
                ? null
                : Colors.white.withValues(alpha: _hover ? 0.06 : 0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.locked) ...[
                Icon(
                  Icons.lock_rounded,
                  size: 13,
                  color: sel ? const Color(0xFF1A1300) : WebPalette.textFaint,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: WebPalette.body(
                  13.5,
                  weight: FontWeight.w700,
                  color: sel ? const Color(0xFF1A1300) : WebPalette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Columna de [WebTable].
class WebColumn<T> {
  final String label;
  final int flex;
  final Widget Function(T row) cell;
  final bool numeric;
  const WebColumn(this.label, this.cell, {this.flex = 1, this.numeric = false});
}

/// Tabla adaptable: en escritorio filas tipo tabla; en móvil tarjetas.
class WebTable<T> extends StatelessWidget {
  final List<WebColumn<T>> columns;
  final List<T> rows;
  final Widget Function(T row)? trailing;
  final void Function(T row)? onRowTap;
  final Widget Function(T row)? mobileTitle;
  final bool Function(T row)? isSelected;

  const WebTable({
    super.key,
    required this.columns,
    required this.rows,
    this.trailing,
    this.onRowTap,
    this.mobileTitle,
    this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 760) return _mobile();
        return _desktop();
      },
    );
  }

  Widget _desktop() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.035),
          ),
          child: Row(
            children: [
              for (final col in columns)
                Expanded(
                  flex: col.flex,
                  child: Text(
                    col.label.toUpperCase(),
                    textAlign: col.numeric ? TextAlign.right : TextAlign.left,
                    style: WebPalette.body(
                      11.5,
                      weight: FontWeight.w700,
                      color: WebPalette.textFaint,
                    ),
                  ),
                ),
              if (trailing != null) const SizedBox(width: 120),
            ],
          ),
        ),
        const SizedBox(height: 6),
        for (final r in rows)
          _HoverRow(
            selected: isSelected?.call(r) ?? false,
            onTap: onRowTap == null ? null : () => onRowTap!(r),
            child: Row(
              children: [
                for (final col in columns)
                  Expanded(
                    flex: col.flex,
                    child: Align(
                      alignment: col.numeric
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: col.cell(r),
                    ),
                  ),
                if (trailing != null)
                  SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing!(r),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mobile() {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HoverRow(
              selected: isSelected?.call(r) ?? false,
              onTap: onRowTap == null ? null : () => onRowTap!(r),
              boxed: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mobileTitle != null || trailing != null)
                    Row(
                      children: [
                        Expanded(
                          child: mobileTitle?.call(r) ?? const SizedBox(),
                        ),
                        if (trailing != null) trailing!(r),
                      ],
                    ),
                  if (mobileTitle != null || trailing != null)
                    const SizedBox(height: 8),
                  for (final col in columns)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              col.label,
                              style: WebPalette.body(
                                12.5,
                                color: WebPalette.textFaint,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: col.cell(r),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HoverRow extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool boxed;
  final bool selected;
  const _HoverRow({
    required this.child,
    this.onTap,
    this.boxed = false,
    this.selected = false,
  });

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.only(bottom: widget.boxed ? 0 : 4),
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: widget.boxed ? 16 : 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.selected
                ? WebPalette.gold.withValues(alpha: 0.10)
                : Colors.white.withValues(
                    alpha: _hover ? 0.05 : (widget.boxed ? 0.035 : 0),
                  ),
            border: Border.all(
              color: widget.selected
                  ? WebPalette.gold.withValues(alpha: 0.45)
                  : (widget.boxed
                        ? WebPalette.glassBorder
                        : Colors.transparent),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Texto principal de celda.
class CellText extends StatelessWidget {
  final String text;
  final bool strong;
  final Color? color;
  final bool mono;
  const CellText(
    this.text, {
    super.key,
    this.strong = false,
    this.color,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    if (mono && text.contains('-')) {
      return BallNumberText(
        text,
        style: WebPalette.display(
          14,
          weight: FontWeight.w700,
          color: color ?? WebPalette.goldLight,
        ),
      );
    }
    return Text(
      text.isEmpty ? '—' : text,
      overflow: TextOverflow.ellipsis,
      style: mono
          ? WebPalette.display(
              14,
              weight: FontWeight.w700,
              color: color ?? WebPalette.goldLight,
            )
          : WebPalette.body(
              14,
              weight: strong ? FontWeight.w700 : FontWeight.w500,
              color: color ?? (strong ? WebPalette.text : WebPalette.textMuted),
            ),
    );
  }
}

/// Balotas pequeñas para listar números.
class NumberPills extends StatelessWidget {
  final List<String> numbers;
  final String? highlight;
  const NumberPills(this.numbers, {super.key, this.highlight});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in numbers)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              gradient: n == highlight ? WebPalette.goldGradient : null,
              color: n == highlight
                  ? null
                  : Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: n == highlight
                    ? Colors.transparent
                    : WebPalette.gold.withValues(alpha: 0.25),
              ),
            ),
            child: BallNumberText(
              n,
              style: WebPalette.display(
                13,
                weight: FontWeight.w700,
                color: n == highlight
                    ? const Color(0xFF1A1300)
                    : WebPalette.goldLight,
              ),
            ),
          ),
      ],
    );
  }
}

/// Estado vacío.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WebPalette.gold.withValues(alpha: 0.08),
              border: Border.all(
                color: WebPalette.gold.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(icon, size: 32, color: WebPalette.goldLight),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: WebPalette.display(17, weight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: WebPalette.body(14),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Bloque de carga con brillo (skeleton).
class SkeletonBlock extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const SkeletonBlock({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 10,
  });

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + _c.value * 3, 0),
            end: Alignment(-0.5 + _c.value * 3, 0),
            colors: [
              Colors.white.withValues(alpha: 0.04),
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista de skeletons para tablas en carga.
class TableSkeleton extends StatelessWidget {
  final int rows;
  const TableSkeleton({super.key, this.rows = 6});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonBlock(height: 46, radius: 12),
          ),
      ],
    );
  }
}

/// Botón de icono con tooltip y estilo de vidrio.
class WebIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final int? badge;

  const WebIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
    this.badge,
  });

  @override
  State<WebIconButton> createState() => _WebIconButtonState();
}

class _WebIconButtonState extends State<WebIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? WebPalette.textMuted;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: _hover ? 0.09 : 0.04),
                  border: Border.all(color: WebPalette.glassBorder),
                ),
                child: Icon(
                  widget.icon,
                  size: 19,
                  color: _hover ? WebPalette.text : c,
                ),
              ),
              if ((widget.badge ?? 0) > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: WebPalette.danger,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: WebPalette.bg, width: 2),
                    ),
                    child: Text(
                      widget.badge! > 99 ? '99+' : '${widget.badge}',
                      textAlign: TextAlign.center,
                      style: WebPalette.body(
                        10,
                        weight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muestra un modal de contenido web (formularios, detalles).
Future<T?> showWebModal<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget Function(BuildContext ctx) builder,
  double maxWidth = 560,
  ThemeData? theme,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, a1, a2) {
      final content = SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 820),
              child: Material(
                color: WebPalette.bgElevated,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: WebPalette.glassBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: WebPalette.display(
                                      20,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: WebPalette.body(13.5),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar',
                              onPressed: () => Navigator.of(ctx).maybePop(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: WebPalette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: WebPalette.glassBorder),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: builder(ctx),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return Theme(data: theme ?? buildWebTheme(), child: content);
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 6 * anim.value,
          sigmaY: 6 * anim.value,
        ),
        child: FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curve),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Panel lateral derecho (notificaciones, detalles).
Future<T?> showWebSidePanel<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext ctx) builder,
  double width = 420,
  ThemeData? theme,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, a1, a2) {
      final w = MediaQuery.sizeOf(ctx).width;
      final panel = Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: WebPalette.bgElevated,
          child: Container(
            width: w < 520 ? w : width,
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: WebPalette.glassBorder)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 10, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: WebPalette.display(
                              19,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: WebPalette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: WebPalette.glassBorder),
                  Expanded(child: builder(ctx)),
                ],
              ),
            ),
          ),
        ),
      );
      return Theme(data: theme ?? buildWebTheme(), child: panel);
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.15, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
}
