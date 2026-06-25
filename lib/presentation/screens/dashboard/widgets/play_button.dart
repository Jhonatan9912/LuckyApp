import 'package:flutter/material.dart';

class PlayButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const PlayButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFFD4AF37), Color(0xFFF5C842), Color(0xFFD4AF37)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66D4AF37),
              blurRadius: 18,
              spreadRadius: 1,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Text(
          'JUGAR',
          style: TextStyle(
            color: Color(0xFF0A0A0A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }
}
