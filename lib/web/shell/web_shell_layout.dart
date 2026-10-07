// lib/web/shell/web_shell_layout.dart
//
// Estructura de la plataforma web: menú lateral + barra superior + contenido.
//  • Escritorio (≥1100px): menú lateral completo.
//  • Tablet (720–1100px): menú lateral compacto (solo íconos).
//  • Móvil (<720px): barra superior con menú desplegable.
import 'package:flutter/material.dart';

import '../theme/web_palette.dart';
import '../theme/web_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/web_ui.dart';

class WebNavItem {
  final IconData icon;
  final String label;
  final int badge;
  const WebNavItem(this.icon, this.label, {this.badge = 0});
}

class WebShellLayout extends StatelessWidget {
  final List<WebNavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final String userName;
  final String userRole;
  final VoidCallback onLogout;
  final Widget body;
  final Widget? sidebarFooter;

  const WebShellLayout({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.userName,
    required this.userRole,
    required this.onLogout,
    required this.body,
    this.sidebarFooter,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < WebBreakpoints.mobile;
    final compact = !mobile && width < WebBreakpoints.tablet;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          title: title,
          subtitle: subtitle,
          actions: actions,
          mobile: mobile,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            // Las páginas ocupan todo el alto, alineadas arriba.
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.015),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(selected), child: body),
          ),
        ),
      ],
    );

    return Theme(
      data: buildWebTheme(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: WebPalette.bg,
          drawer: mobile
              ? Drawer(
                  backgroundColor: WebPalette.bgElevated,
                  width: 290,
                  child: _Sidebar(
                    items: items,
                    selected: selected,
                    onSelect: (i) {
                      Navigator.of(context).pop();
                      onSelect(i);
                    },
                    compact: false,
                    userName: userName,
                    userRole: userRole,
                    onLogout: onLogout,
                    footer: sidebarFooter,
                  ),
                )
              : null,
          body: AuroraBackground(
            showGrid: false,
            animate: false,
            child: mobile
                ? content
                : Row(
                    children: [
                      _Sidebar(
                        items: items,
                        selected: selected,
                        onSelect: onSelect,
                        compact: compact,
                        userName: userName,
                        userRole: userRole,
                        onLogout: onLogout,
                        footer: sidebarFooter,
                      ),
                      Expanded(child: content),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool mobile;

  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.mobile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        mobile ? 8 : 32,
        mobile ? 10 : 22,
        mobile ? 12 : 32,
        mobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: WebPalette.glassBorder)),
        color: WebPalette.bg.withValues(alpha: 0.35),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (mobile) ...[
              IconButton(
                tooltip: 'Menú',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded, color: WebPalette.text),
              ),
              Image.asset('assets/icons/iconowithout.png', width: 30),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: WebPalette.display(
                      mobile ? 18 : 26,
                      weight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null && !mobile) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: WebPalette.body(14)),
                  ],
                ],
              ),
            ),
            for (final a in actions) ...[const SizedBox(width: 10), a],
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<WebNavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool compact;
  final String userName;
  final String userRole;
  final VoidCallback onLogout;
  final Widget? footer;

  const _Sidebar({
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.compact,
    required this.userName,
    required this.userRole,
    required this.onLogout,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final initials = userName.trim().isEmpty
        ? '?'
        : userName
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0])
              .join()
              .toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: compact ? 84 : 268,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(right: BorderSide(color: WebPalette.glassBorder)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 0 : 22,
                24,
                compact ? 0 : 22,
                28,
              ),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: WebPalette.gold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Image.asset('assets/icons/iconowithout.png'),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CM APP',
                          style: WebPalette.display(
                            18,
                            weight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Juega · Gana · Comparte',
                          style: WebPalette.body(
                            11,
                            color: WebPalette.textFaint,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 0, 22, 10),
                child: Text(
                  'MENÚ',
                  style: WebPalette.body(
                    11,
                    weight: FontWeight.w800,
                    color: WebPalette.textFaint,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 14),
                children: [
                  for (var i = 0; i < items.length; i++)
                    _NavTile(
                      item: items[i],
                      selected: i == selected,
                      compact: compact,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
            if (footer != null && !compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: footer!,
              ),
            Container(
              margin: EdgeInsets.fromLTRB(
                compact ? 12 : 14,
                0,
                compact ? 12 : 14,
                16,
              ),
              padding: EdgeInsets.all(compact ? 8 : 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: WebPalette.glassBorder),
              ),
              child: compact
                  ? Column(
                      children: [
                        _Avatar(initials: initials),
                        const SizedBox(height: 8),
                        IconButton(
                          tooltip: 'Cerrar sesión',
                          onPressed: onLogout,
                          icon: const Icon(
                            Icons.logout_rounded,
                            size: 19,
                            color: WebPalette.textMuted,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        _Avatar(initials: initials),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName.isEmpty ? 'Mi cuenta' : userName,
                                overflow: TextOverflow.ellipsis,
                                style: WebPalette.body(
                                  13.5,
                                  weight: FontWeight.w700,
                                  color: WebPalette.text,
                                ),
                              ),
                              Text(
                                userRole,
                                style: WebPalette.body(
                                  12,
                                  color: WebPalette.textFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar sesión',
                          onPressed: onLogout,
                          icon: const Icon(
                            Icons.logout_rounded,
                            size: 19,
                            color: WebPalette.textMuted,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  const _Avatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: WebPalette.goldGradient,
      ),
      child: Text(
        initials,
        style: WebPalette.body(
          13,
          weight: FontWeight.w800,
          color: const Color(0xFF1A1300),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  final WebNavItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 0 : 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: sel
                ? LinearGradient(
                    colors: [
                      WebPalette.gold.withValues(alpha: 0.22),
                      WebPalette.gold.withValues(alpha: 0.04),
                    ],
                  )
                : null,
            color: sel
                ? null
                : Colors.white.withValues(alpha: _hover ? 0.05 : 0),
            border: Border.all(
              color: sel
                  ? WebPalette.gold.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    widget.item.icon,
                    size: 21,
                    color: sel
                        ? WebPalette.goldLight
                        : (_hover ? WebPalette.text : WebPalette.textMuted),
                  ),
                  if (widget.compact && widget.item.badge > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: WebPalette.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: WebPalette.body(
                      14.5,
                      weight: sel ? FontWeight.w700 : FontWeight.w600,
                      color: sel ? WebPalette.text : WebPalette.textMuted,
                    ),
                  ),
                ),
                if (widget.item.badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: WebPalette.danger.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${widget.item.badge}',
                      style: WebPalette.body(
                        11.5,
                        weight: FontWeight.w800,
                        color: WebPalette.danger,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.compact
        ? Tooltip(message: widget.item.label, child: tile)
        : tile;
  }
}

/// Contenedor de página con scroll y márgenes consistentes.
class WebPage extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;

  const WebPage({super.key, required this.children, this.maxWidth = 1320});

  @override
  Widget build(BuildContext context) {
    final mobile = WebBreakpoints.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        mobile ? 14 : 32,
        mobile ? 16 : 26,
        mobile ? 14 : 32,
        40,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
