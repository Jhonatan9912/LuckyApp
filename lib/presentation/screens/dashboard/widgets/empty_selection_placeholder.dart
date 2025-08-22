import 'package:flutter/material.dart';

class EmptySelectionPlaceholder extends StatelessWidget {
  const EmptySelectionPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'assets/images/empty_placeholder.png',
        width: 280, // ⬅️ Aumentamos el tamaño
        fit: BoxFit.contain,
      ),
    );
  }
}
