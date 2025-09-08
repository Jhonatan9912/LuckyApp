import 'package:meta/meta.dart';

@immutable
class AdminUserDetail {
  final int userId;

  /// Nombre completo del referido (el dueño de la comisión).
  final String fullName;

  /// Número de identificación (cédula, etc.)
  final String idNumber;

  /// Estado de suscripción del referido.
  final bool isPro;

  /// Nombre completo del beneficiario al que se le va a pagar (puede coincidir
  /// con el referido o ser un titular distinto de la cuenta).
  final String payeeFullName;

  // --- Datos bancarios ---
  /// Tipo de cuenta/medio: 'bank' | 'nequi' | 'daviplata' | 'other'
  final String accountType;

  /// Banco o proveedor (p.ej. 'Bancolombia', 'NEQUI', 'DAVIPLATA').
  final String providerName;

  /// Número de cuenta o número de celular (si es SEDPE).
  final String accountNumber;

  /// Tipo de cuenta bancaria: 'savings' | 'checking' (si aplica).
  final String? bankKind;

  /// Número de identificación del titular de la cuenta (beneficiario).
  final String payeeIdNumber;

  /// Observaciones del administrador sobre esta solicitud/pago.
  final String? observations; // 👈 NUEVO

  const AdminUserDetail({
    required this.userId,
    required this.fullName,
    required this.idNumber,
    required this.isPro,
    required this.payeeFullName,
    required this.accountType,
    required this.providerName,
    required this.accountNumber,
    required this.payeeIdNumber,
    this.bankKind,
    this.observations, // 👈 NUEVO
  });

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) {
    return AdminUserDetail(
      userId: json['user_id'] as int,
      fullName: (json['full_name'] ?? '').toString(),
      idNumber: (json['id_number'] ?? '').toString(),
      isPro: (json['is_pro'] ?? false) as bool,
      payeeFullName: (json['payee_full_name'] ?? '').toString(),
      accountType: (json['account_type'] ?? '').toString(),
      providerName: (json['provider_name'] ?? '').toString(),
      accountNumber: (json['account_number'] ?? '').toString(),
      bankKind: json['bank_kind']?.toString(),
      payeeIdNumber: (json['payee_id_number'] ?? '').toString(),
      observations: ((json['observations'] ?? json['admin_note']) ?? '')
          .toString(),
    );
  }
}
