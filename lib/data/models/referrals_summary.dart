// lib/data/models/referrals_summary.dart

/// Modelo para el resumen de referidos (total / activos / inactivos / comisiones).
class ReferralsSummary {
  final int total;
  final int active;
  final int inactive;

  /// Comisiones pendientes en COP
  final int pendingCop;

  /// Comisiones pagadas en COP
  final int paidCop;

  /// Código de moneda (ej: "COP")
  final String currency;

  const ReferralsSummary({
    required this.total,
    required this.active,
    required this.inactive,
    required this.pendingCop,
    required this.paidCop,
    required this.currency,
  });

  /// Crea una instancia segura desde cualquier mapa dinámico.
  factory ReferralsSummary.fromMap(Map<String, dynamic> map) {
    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return ReferralsSummary(
      total: toInt(map['total']),
      active: toInt(map['active']),
      inactive: toInt(map['inactive']),
      pendingCop: toInt(map['pending_cop']),
      paidCop: toInt(map['paid_cop']),
      currency: map['currency']?.toString() ?? 'COP',
    );
  }

  /// Útil si pasas directamente el body decodificado del backend:
  /// { ok: true, total: 10, active: 6, inactive: 4, pending_cop: 12000, paid_cop: 5000, currency: "COP" }
  factory ReferralsSummary.fromApiResponse(Map<String, dynamic> body) {
    return ReferralsSummary.fromMap(body);
  }

  Map<String, dynamic> toMap() => {
        'total': total,
        'active': active,
        'inactive': inactive,
        'pending_cop': pendingCop,
        'paid_cop': paidCop,
        'currency': currency,
      };

  ReferralsSummary copyWith({
    int? total,
    int? active,
    int? inactive,
    int? pendingCop,
    int? paidCop,
    String? currency,
  }) {
    return ReferralsSummary(
      total: total ?? this.total,
      active: active ?? this.active,
      inactive: inactive ?? this.inactive,
      pendingCop: pendingCop ?? this.pendingCop,
      paidCop: paidCop ?? this.paidCop,
      currency: currency ?? this.currency,
    );
  }

  @override
  String toString() =>
      'ReferralsSummary(total=$total, active=$active, inactive=$inactive, pending=$pendingCop, paid=$paidCop, currency=$currency)';

  @override
  bool operator ==(Object other) {
    return other is ReferralsSummary &&
        other.total == total &&
        other.active == active &&
        other.inactive == inactive &&
        other.pendingCop == pendingCop &&
        other.paidCop == paidCop &&
        other.currency == currency;
  }

  @override
  int get hashCode =>
      Object.hash(total, active, inactive, pendingCop, paidCop, currency);
}
