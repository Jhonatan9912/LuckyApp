class TopReferrer {
  final int userId;
  final String name;
  final String phone;
  final int activeCount;
  final String status; // 'FREE' | 'PRO'

  const TopReferrer({
    required this.userId,
    required this.name,
    required this.phone,
    required this.activeCount,
    required this.status,
  });

  factory TopReferrer.fromMap(Map<String, dynamic> map) {
    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    String toStr(dynamic v, [String def = '']) =>
        (v == null ? def : v.toString());

    String toStatus(dynamic v) {
      final s = toStr(v).trim().toUpperCase();
      return s == 'PRO' ? 'PRO' : 'FREE';
    }

    return TopReferrer(
      userId: toInt(map['user_id'] ?? map['userId']),
      name: toStr(map['name'], '—'),
      phone: toStr(map['phone']),
      activeCount: toInt(map['active_count'] ?? map['activeCount']),
      status: toStatus(map['status']),
    );
  }
}
