import 'package:flutter/material.dart';

class SelectionTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final bool historyUnlocked;
  final VoidCallback? onHistoryLocked;

  const SelectionTabs({
    super.key,
    required this.index,
    required this.onChanged,
    this.historyUnlocked = true,
    this.onHistoryLocked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEAD88A), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22D4AF37),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _TabButton(
            label: 'Juego',
            active: index == 0,
            onTap: () => onChanged(0),
          ),
          _TabButton(
            label: historyUnlocked ? 'Historial' : 'Historial 🔒',
            active: index == 1,
            onTap: historyUnlocked
                ? () => onChanged(1)
                : () => onHistoryLocked?.call(),
          ),
          _TabButton(
            label: 'Referidos',
            active: index == 2,
            onTap: () => onChanged(2),
          ),
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.all(3),
          alignment: Alignment.center,
          decoration: active
              ? BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD4AF37), Color(0xFFC09000)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44D4AF37),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                )
              : null,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: active ? const Color(0xFF0A0A0A) : const Color(0xFF8B7030),
            ),
          ),
        ),
      ),
    );
  }
}
