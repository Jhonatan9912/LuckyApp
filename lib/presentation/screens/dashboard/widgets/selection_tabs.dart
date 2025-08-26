import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:base_app/presentation/providers/subscription_provider.dart';

class SelectionTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const SelectionTabs({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    assert(index >= 0 && index <= 2, 'index debe ser 0, 1 o 2');

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
      child: Selector<SubscriptionProvider, bool>(
        selector: (_, p) => p.isPremium,
        builder: (context, isPremium, _) {
          return Row(
            children: [
              _TabButton(
                label: 'Juego Actual',
                active: index == 0,
                onTap: () => onChanged(0),
              ),
              _TabButton(
                label: isPremium ? 'Historial' : 'Historial 🔒',
                active: index == 1,
                onTap: () {
                  if (isPremium) {
                    onChanged(1);
                  } else {
                    // paywall sin cambiar de pestaña
                    Navigator.pushNamed(context, '/pro');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Esta sección es solo para PRO')),
                    );
                  }
                },
              ),
              _TabButton(
                label: 'Mis referidos',
                active: index == 2,
                onTap: () => onChanged(2),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBg = const Color(0xFF7C4DFF).withValues(alpha: 0.15);
    final selectedFg = const Color(0xFF7C4DFF);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: active ? selectedFg : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}
