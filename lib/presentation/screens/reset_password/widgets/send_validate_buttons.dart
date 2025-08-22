import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SendValidateButtons extends StatelessWidget {
  final Future<void> Function()? onSend;
  final Future<void> Function()? onValidate;
  final bool codeSent;
  final bool loadingSend;
  final bool loadingValidate;

  const SendValidateButtons({
    super.key,
    required this.onSend,
    required this.onValidate,
    required this.codeSent,
    this.loadingSend = false,
    this.loadingValidate = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = codeSent ? loadingValidate : loadingSend;

    return ElevatedButton(
      onPressed: isLoading
          ? null
          : () {
              if (codeSent) {
                onValidate?.call();
              } else {
                onSend?.call();
              }
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber[800],
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Text(
              codeSent ? 'Validar código' : 'Enviar código',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
    );
  }
}
