import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CodeInput extends StatelessWidget {
  final TextEditingController controller;
  const CodeInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: GoogleFonts.montserrat(),
      decoration: InputDecoration(
        labelText: 'Código de verificación',
        labelStyle: GoogleFonts.montserrat(),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
