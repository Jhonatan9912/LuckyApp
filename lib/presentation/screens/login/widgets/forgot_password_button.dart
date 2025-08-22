import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../reset_password/reset_password_screen.dart';

class ForgotPasswordButton extends StatelessWidget {
  const ForgotPasswordButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ResetPasswordScreen(),
            ),
          );
        },
        child: Text(
          'Restablecer contraseña',
          style: GoogleFonts.montserrat(
            color: Colors.deepPurple[700],
            fontSize: 14,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
