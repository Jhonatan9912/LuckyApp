import 'package:flutter/material.dart';

class IdentificationNumberInput extends StatelessWidget {
  final TextEditingController controller;

  const IdentificationNumberInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 15,
      decoration: const InputDecoration(
        labelText: 'Número de identificación',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Este campo es obligatorio';
        }
        if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
          return 'Solo se permiten números';
        }
        if (value.length < 6) {
          return 'Debe tener al menos 6 dígitos';
        }
        return null;
      },
    );
  }
}
