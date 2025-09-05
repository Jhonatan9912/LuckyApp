// lib/domain/models/bank.dart
class Bank {
  final String code;        // código interno estable (preferido por tu backend)
  final String name;
  final String shortName;
  final String entityType;  // BANK | CF | SEDPE | ...
  final String countryCode; // 'CO'
  final bool active;
  final String? achCode;
  final String? swiftBic;
  final String? pseCode;

  Bank({
    required this.code,
    required this.name,
    required this.shortName,
    required this.entityType,
    required this.countryCode,
    required this.active,
    this.achCode,
    this.swiftBic,
    this.pseCode,
  });

  /// Normaliza un booleano que puede venir como bool/num/string.
  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 't' || s == 'y' || s == 'yes';
  }

  /// Slug muy básico para generar un code de respaldo si el backend no lo envía.
  static String _slug(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return base.isEmpty ? 'bank' : base;
  }

  factory Bank.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? j['bank_name'] ?? '').toString().trim();
    final shortNameRaw =
        (j['short_name'] ?? j['shortName'] ?? '').toString().trim();
    final shortName =
        shortNameRaw.isNotEmpty ? shortNameRaw : (name.isNotEmpty ? name : '');

    // Intenta tomar un code estable; si no viene, usa algún identificador conocido
    // y como último recurso un slug del shortName/name.
    final candidateCode = (j['code'] ??
            j['bank_code'] ??
            j['pse_code'] ??
            j['ach_code'] ??
            j['swift_bic'] ??
            j['id'])
        ?.toString()
        .trim();

    final code = (candidateCode == null || candidateCode.isEmpty)
        ? _slug(shortName.isNotEmpty ? shortName : name)
        : candidateCode;

    final entityType =
        (j['entity_type'] ?? j['entityType'] ?? j['type'] ?? 'BANK')
            .toString()
            .toUpperCase();

    final countryCode =
        (j['country_code'] ?? j['countryCode'] ?? 'CO').toString().toUpperCase();

    return Bank(
      code: code,
      name: name,
      shortName: shortName,
      entityType: entityType,
      countryCode: countryCode,
      active: _asBool(j['active']),
      achCode: j['ach_code']?.toString(),
      swiftBic: j['swift_bic']?.toString(),
      pseCode: j['pse_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'short_name': shortName,
        'entity_type': entityType,
        'country_code': countryCode,
        'active': active,
        'ach_code': achCode,
        'swift_bic': swiftBic,
        'pse_code': pseCode,
      };

  /// Útil para dropdowns
  @override
  String toString() => shortName.isNotEmpty ? shortName : name;
}
