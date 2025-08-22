import 'package:flutter/material.dart';

class SelectionTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const SelectionTabs({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isJuego = index == 0;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _TabButton(label: 'Juego Actual', active: isJuego, onTap: () => onChanged(0)),
          _TabButton(label: 'Historial', active: !isJuego, onTap: () => onChanged(1)),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF7C4DFF).withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: active ? const Color(0xFF7C4DFF) : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}
