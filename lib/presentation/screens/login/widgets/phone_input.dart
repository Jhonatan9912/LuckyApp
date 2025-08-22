import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class PhoneInput extends StatelessWidget {
  final TextEditingController controller;

  const PhoneInput({super.key, required this.controller});

  String? _validator(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ingresa tu número de celular';
    if (!RegExp(r'^\d+$').hasMatch(v)) return 'Solo dígitos';
    // Rango típico: 10 dígitos CO, permitimos 10–13 por compatibilidad internacional
    if (v.length < 10 || v.length > 13) return 'Número inválido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: _validator,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(13),
              ],
              decoration: InputDecoration(
                labelText: 'Número de celular',
                hintText: 'Ej: 3001234567',
                labelStyle: GoogleFonts.montserrat(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.phone),
              ),
              onChanged: (_) => state.didChange(controller.text),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  state.errorText!,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.red[700],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
