import 'package:flutter/material.dart';

class SelectedBallSet extends StatelessWidget {
  final List<int> numbers;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const SelectedBallSet({
    super.key,
    required this.numbers,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mostrar las balotas
          ...numbers.map((n) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.amber,
                ),
                child: Text(
                  n.toString().padLeft(3, '0'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              )),

          const SizedBox(width: 12),

          // Botón Editar
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit, color: Colors.blueGrey),
            tooltip: 'Editar',
          ),

          // Botón Eliminar
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }
}
