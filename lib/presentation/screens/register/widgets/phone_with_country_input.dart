import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'phone_input.dart';

class PhoneWithCountryInput extends StatelessWidget {
  final TextEditingController countryCodeController;
  final TextEditingController phoneController;

  const PhoneWithCountryInput({
    super.key,
    required this.countryCodeController,
    required this.phoneController,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Campo de código de país
        SizedBox(
          width: 90,
          child: TextField(
            controller: countryCodeController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: GoogleFonts.montserrat(),
            decoration: InputDecoration(
              labelText: 'Código',
              hintText: '+57',
              labelStyle: GoogleFonts.montserrat(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Reutilizamos tu PhoneInput existente
        Expanded(child: PhoneInput(controller: phoneController)),
      ],
    );
  }
}
