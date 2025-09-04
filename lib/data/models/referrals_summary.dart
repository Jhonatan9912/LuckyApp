// lib/data/models/referrals_summary.dart

/// Modelo para el resumen de referidos (total / activos / inactivos).
class ReferralsSummary {
  final int total;
  final int active;
  final int inactive;

  const ReferralsSummary({
    required this.total,
    required this.active,
    required this.inactive,
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
    );
  }

  /// Útil si pasas directamente el body decodificado del backend:
  /// { ok: true, total: 10, active: 6, inactive: 4 }
  factory ReferralsSummary.fromApiResponse(Map<String, dynamic> body) {
    return ReferralsSummary.fromMap(body);
  }

  Map<String, dynamic> toMap() => {
        'total': total,
        'active': active,
        'inactive': inactive,
      };

  ReferralsSummary copyWith({
    int? total,
    int? active,
    int? inactive,
  }) {
    return ReferralsSummary(
      total: total ?? this.total,
      active: active ?? this.active,
      inactive: inactive ?? this.inactive,
    );
  }

  @override
  String toString() =>
      'ReferralsSummary(total=$total, active=$active, inactive=$inactive)';

  @override
  bool operator ==(Object other) {
    return other is ReferralsSummary &&
        other.total == total &&
        other.active == active &&
        other.inactive == inactive;
  }

  @override
  int get hashCode => Object.hash(total, active, inactive);
}
