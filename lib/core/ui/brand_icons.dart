import 'package:flutter/widgets.dart';

/// Íconos de marca (Font Awesome Brands) empaquetados como fuente propia.
/// Sustituye a font_awesome_flutter, que obligaba a descargar en la web las
/// fuentes Solid y Regular completas (~480 KB) aunque no se usaran.
class BrandIcons {
  BrandIcons._();

  static const String _family = 'FaBrands';

  static const IconData whatsapp = IconData(0xf232, fontFamily: _family);
  static const IconData facebookF = IconData(0xf39e, fontFamily: _family);
}
