import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ReferralCheckboxWithInput extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final TextEditingController controller;

  const ReferralCheckboxWithInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Colors.deepPurple[700];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: accent,
          checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Text(
            '¿Fuiste referido?',
            style: GoogleFonts.montserrat(fontSize: 14, color: Colors.grey[800]),
          ),
        ),
        if (value) ...[
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Código de referido',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }
}
