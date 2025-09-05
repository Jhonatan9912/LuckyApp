// lib/domain/models/payout_request.dart

class PayoutRequestInput {
  /// 'bank' | 'nequi' | 'daviplata' | 'bancolombia_cell' | 'other'
  final String accountType;

  /// 'savings' | 'checking' (solo si accountType == 'bank')
  final String? accountKind;

  /// Número de cuenta o celular (según accountType)
  final String accountNumber;

  /// Código del banco (si accountType == 'bank')
  final String? bankCode;

  /// Observaciones opcionales que envía el usuario
  final String? observations;

  PayoutRequestInput({
    required this.accountType,
    this.accountKind,
    required this.accountNumber,
    this.bankCode,
    this.observations,
  })  : assert(
          accountNumber.trim().isNotEmpty,
          'accountNumber no puede estar vacío',
        ),
        assert(
          accountType.toLowerCase() != 'bank' ||
              (bankCode != null &&
                  bankCode.trim().isNotEmpty &&
                  accountKind != null &&
                  accountKind.trim().isNotEmpty),
          "Para accountType=bank debes enviar bankCode y accountKind ('savings'|'checking')",
        ),
        assert(
          accountType.toLowerCase() == 'bank' ||
              (bankCode == null && accountKind == null),
          "Para accountType distinto de 'bank' no envíes bankCode ni accountKind",
        ),
        assert(
          const {
            'bank',
            'nequi',
            'daviplata',
            'bancolombia_cell',
            'other',
          }.contains(accountType.toLowerCase()),
          "accountType inválido",
        );

  Map<String, dynamic> toJson() => {
        'account_type': accountType.toLowerCase().trim(),
        if (accountKind != null) 'account_kind': accountKind!.toLowerCase().trim(),
        'account_number': accountNumber.trim(),
        if (bankCode != null) 'bank_code': bankCode!.trim(),
        if (observations != null && observations!.isNotEmpty)
          'observations': observations,
      };

  @override
  String toString() =>
      'PayoutRequestInput('
      'type=$accountType, '
      'kind=$accountKind, '
      'number=$accountNumber, '
      'bank=$bankCode, '
      'obs=$observations'
      ')';
}

/// Modelo de respuesta al crear/consultar una solicitud de retiro.
class PayoutRequest {
  final int id;
  final int amountMicros;
  final String currencyCode; // p. ej. 'COP'
  final String status;       // p. ej. 'pending', 'processing', 'paid', 'rejected'
  final DateTime? requestedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayoutRequest({
    required this.id,
    required this.amountMicros,
    required this.currencyCode,
    required this.status,
    this.requestedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Conveniencia: monto en COP (si tu moneda base es COP).
  double get amountCop => amountMicros / 1_000_000.0;

  factory PayoutRequest.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return PayoutRequest(
      id: asInt(j['id'] ?? j['request_id']),
      amountMicros: asInt(j['amount_micros'] ?? j['amountMicros']),
      currencyCode:
          (j['currency_code'] ?? j['currencyCode'] ?? 'COP').toString(),
      status: (j['status'] ?? '').toString(),
      requestedAt: asDate(j['requested_at'] ?? j['requestedAt']),
      createdAt: asDate(j['created_at'] ?? j['createdAt']),
      updatedAt: asDate(j['updated_at'] ?? j['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount_micros': amountMicros,
        'currency_code': currencyCode,
        'status': status,
        'requested_at': requestedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  @override
  String toString() =>
      'PayoutRequest(id=$id, amountMicros=$amountMicros, '
      'currency=$currencyCode, status=$status, '
      'requestedAt=$requestedAt, createdAt=$createdAt, updatedAt=$updatedAt)';
}
