import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PhoneInput extends StatelessWidget {
  final TextEditingController controller;
  const PhoneInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      style: GoogleFonts.montserrat(),
      decoration: InputDecoration(
        labelText: 'Número de teléfono',
        labelStyle: GoogleFonts.montserrat(),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
