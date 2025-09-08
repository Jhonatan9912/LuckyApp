import 'package:meta/meta.dart';

@immutable
class CommissionBreakdownItem {
  final int referredUserId;
  final String publicCode;
  final String name;
  final String idNumber;
  final bool isPro;
  final int commissionCop;
  final DateTime? createdAt;

  const CommissionBreakdownItem({
    required this.referredUserId,
    required this.publicCode,
    required this.name,
    required this.idNumber,
    required this.isPro,
    required this.commissionCop,
    this.createdAt,
  });

  factory CommissionBreakdownItem.fromJson(Map<String, dynamic> json) {
    return CommissionBreakdownItem(
      referredUserId: json['referred_user_id'] as int,
      publicCode: (json['public_code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      idNumber: (json['id_number'] ?? '').toString(),
      isPro: (json['is_pro'] ?? false) as bool,
      commissionCop: (json['commission_cop'] ?? 0) as int,
      createdAt: json['created_at'] != null && (json['created_at'] as String).isNotEmpty
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

@immutable
class CommissionRequestBreakdown {
  final int requestId;
  final int userId;            // referrer que solicita el pago
  final int requestedCop;      // monto solicitado en la payout_request
  final String currency;
  final List<CommissionBreakdownItem> items;
  final int itemsTotalCop;     // suma de los items
  final bool matchesRequest;   // itemsTotalCop == requestedCop
  final String adminNote; 

  const CommissionRequestBreakdown({
    required this.requestId,
    required this.userId,
    required this.requestedCop,
    required this.currency,
    required this.items,
    required this.itemsTotalCop,
    required this.matchesRequest,
    required this.adminNote,
  });

  factory CommissionRequestBreakdown.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(CommissionBreakdownItem.fromJson)
        .toList();

    return CommissionRequestBreakdown(
      requestId: json['request_id'] as int,
      userId: json['user_id'] as int,
      requestedCop: (json['requested_cop'] ?? 0) as int,
      currency: (json['currency'] ?? 'COP').toString(),
      items: rawItems,
      itemsTotalCop: (json['items_total_cop'] ?? 0) as int,
      matchesRequest: (json['matches_request'] ?? false) as bool,
      adminNote: (json['admin_note'] ?? '').toString(),
    );
  }
}
