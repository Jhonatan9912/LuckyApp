import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ConsentCheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String prefix;
  final String linkText;
  final VoidCallback onTapLink;

  const ConsentCheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.prefix,
    required this.linkText,
    required this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Colors.deepPurple[700];

    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: accent,
      checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$prefix ',
              style: GoogleFonts.montserrat(fontSize: 14, color: Colors.grey[800]),
            ),
            TextSpan(
              text: linkText,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
              recognizer: TapGestureRecognizer()..onTap = onTapLink,
            ),
          ],
        ),
      ),
    );
  }
}
