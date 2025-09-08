// lib/domain/models/commission_request.dart
class CommissionRequest {
  final int id; // payout_requests.id
  final int userId;
  final String userName; // "Nombre (PRO)" si así lo mandas desde backend
  final String monthLabel; // "Sep 2025" (o vacío si no aplica)
  final int amountMicros; // monto total en micros
  final String currency; // p.ej. 'COP'
  final String status; // 'requested' | 'processing' | 'paid' | etc.
  final DateTime createdAt;
  final String adminNote;

  const CommissionRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.monthLabel,
    required this.amountMicros,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.adminNote,
  });

  double get amountCop => amountMicros / 1_000_000.0;

  factory CommissionRequest.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

    DateTime asDate(dynamic v) =>
        v is DateTime ? v : DateTime.parse(v.toString());

    return CommissionRequest(
      id: asInt(j['id'] ?? j['request_id']),
      userId: asInt(j['user_id'] ?? j['userId']),
      userName: (j['user_name'] ?? j['userName'] ?? 'Usuario').toString(),
      monthLabel: (j['month_label'] ?? j['period'] ?? '').toString(),
      amountMicros: asInt(j['amount_micros'] ?? j['amountMicros']),
      currency: (j['currency'] ?? j['currency_code'] ?? 'COP').toString(),
      status: (j['status'] ?? '').toString(),
      createdAt: asDate(j['created_at'] ?? j['createdAt']),
      adminNote: (j['admin_note'] ?? '').toString(), // 👈 CORREGIDO
    );
  }
}
