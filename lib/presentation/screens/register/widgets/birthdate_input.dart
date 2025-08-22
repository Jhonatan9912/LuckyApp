import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BirthDateInput extends StatelessWidget {
  final TextEditingController controller;
  const BirthDateInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () async {
        final now = DateTime.now();
        // 👇 Calcula la fecha máxima permitida (18 años atrás desde hoy)
        final lastAllowed = DateTime(now.year - 18, now.month, now.day);

        final picked = await showDatePicker(
          context: context,
          initialDate: lastAllowed,       // inicia justo en 18 años atrás
          firstDate: DateTime(1900),      // el mínimo permitido
          lastDate: lastAllowed,          // el máximo permitido (18+)
          helpText: 'Selecciona tu fecha de nacimiento',
          locale: const Locale('es', 'CO'),
        );

        if (picked != null) {
          controller.text = '${picked.day}/${picked.month}/${picked.year}';
        }
      },
      style: GoogleFonts.montserrat(),
      decoration: InputDecoration(
        labelText: 'Fecha de nacimiento',
        labelStyle: GoogleFonts.montserrat(),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: const Icon(Icons.calendar_today),
      ),
    );
  }
}
