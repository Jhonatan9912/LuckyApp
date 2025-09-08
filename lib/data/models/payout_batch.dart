// lib/data/models/payout_batch.dart

class PayoutBatch {
  final int id;
  final DateTime? createdAt;
  final String currency;
  final int items;

  /// Total expresado en COP (entero, sin decimales).
  final int totalCop;
  final bool hasFiles;

  /// Extras que devuelve /api/admin/referrals/payout-batches
  final int? firstUserId;
  final String? firstUserName;
  final String? firstUserCode; // 👈 public_code del usuario (si items == 1)
  final String? code; // Ej: PB-000123 (código del lote)

  const PayoutBatch({
    required this.id,
    required this.createdAt,
    required this.currency,
    required this.items,
    required this.totalCop,
    required this.hasFiles,
    this.firstUserId,
    this.firstUserName,
    this.firstUserCode,
    this.code,
  });

  PayoutBatch copyWith({
    int? id,
    DateTime? createdAt,
    String? currency,
    int? items,
    int? totalCop,
    bool? hasFiles,
    int? firstUserId,
    String? firstUserName,
    String? firstUserCode,
    String? code,
  }) {
    return PayoutBatch(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      currency: currency ?? this.currency,
      items: items ?? this.items,
      totalCop: totalCop ?? this.totalCop,
      hasFiles: hasFiles ?? this.hasFiles,
      firstUserId: firstUserId ?? this.firstUserId,
      firstUserName: firstUserName ?? this.firstUserName,
      firstUserCode: firstUserCode ?? this.firstUserCode,
      code: code ?? this.code,
    );
  }

  factory PayoutBatch.fromJson(Map<String, dynamic> json) {
    return PayoutBatch(
      id: _toInt(json['id']),
      createdAt: _parseDate(json['created_at']),
      currency: (json['currency'] ?? 'COP') as String,
      items: _toInt(json['items']),
      totalCop: _toInt(json['total_cop']),
      hasFiles: _toBool(json['has_files'] ?? json['hasFiles'] ?? true),
      firstUserId:
          json['first_user_id'] == null ? null : _toInt(json['first_user_id']),
      firstUserName: json['first_user_name'] as String?,
      firstUserCode: json['first_user_code'] as String?, // 👈 NUEVO
      code: json['code'] as String?,
    );
  }

  /// Helper para listas: convierte una lista dinámica a `List<PayoutBatch>`.
  static List<PayoutBatch> listFromJson(List<dynamic> data) {
    return data
        .map((e) => PayoutBatch.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'currency': currency,
      'items': items,
      'total_cop': totalCop,
      'has_files': hasFiles,
      'first_user_id': firstUserId,
      'first_user_name': firstUserName,
      'first_user_code': firstUserCode, // 👈 NUEVO
      'code': code,
    };
  }

  // ---- Helpers privados para parseo JSON ----
  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  /// Formatea COP sin decimales: 45000 -> "$45.000"
  String get totalCopLabel => _fmtCop(totalCop);

  static String _fmtCop(int value) {
    final s = value.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idxFromRight = s.length - i;
      buf.write(s[i]);
      final isThousandSepSpot = idxFromRight > 1 && (idxFromRight - 1) % 3 == 0;
      if (isThousandSepSpot) buf.write('.');
    }
    final sign = value < 0 ? '-' : '';
    return '$sign\$${buf.toString()}';
  }

  @override
  String toString() {
    return 'PayoutBatch(id: $id, createdAt: $createdAt, currency: $currency, items: $items, totalCop: $totalCop, hasFiles: $hasFiles, firstUserId: $firstUserId, firstUserName: $firstUserName, firstUserCode: $firstUserCode, code: $code)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PayoutBatch &&
            other.id == id &&
            other.createdAt == createdAt &&
            other.currency == currency &&
            other.items == items &&
            other.totalCop == totalCop &&
            other.hasFiles == hasFiles &&
            other.firstUserId == firstUserId &&
            other.firstUserName == firstUserName &&
            other.firstUserCode == firstUserCode &&
            other.code == code);
  }

  @override
  int get hashCode => Object.hash(
        id,
        createdAt,
        currency,
        items,
        totalCop,
        hasFiles,
        firstUserId,
        firstUserName,
        firstUserCode,
        code,
      );
}
