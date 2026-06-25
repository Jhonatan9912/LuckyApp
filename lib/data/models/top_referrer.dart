// data/models/top_referrer.dart

class ActiveReferredUser {
  final int userId;
  final String name;
  final String phone;
  final String status; // 'FREE' | 'PRO'
  final DateTime? subscriptionDate; // 👈 NUEVO

  const ActiveReferredUser({
    required this.userId,
    required this.name,
    required this.phone,
    required this.status,
    this.subscriptionDate, // 👈 NUEVO
  });

  factory ActiveReferredUser.fromMap(Map<String, dynamic> map) {
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

    DateTime? toDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return ActiveReferredUser(
      userId: toInt(map['user_id'] ?? map['userId']),
      name: toStr(map['name'], '—'),
      phone: toStr(map['phone']),
      status: toStatus(map['status']),
      subscriptionDate:
          toDate(map['subscription_date'] ?? map['subscriptionDate']), // 👈 NUEVO
    );
  }
}

class TopReferrer {
  final int userId;
  final String name;
  final String phone;
  final int activeCount;
  final String status; // 'FREE' | 'PRO'
  final List<ActiveReferredUser> activeUsers; // 👈 NUEVO

  const TopReferrer({
    required this.userId,
    required this.name,
    required this.phone,
    required this.activeCount,
    required this.status,
    this.activeUsers = const [],
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

    final List<dynamic> rawUsers =
        (map['active_users'] ?? map['activeUsers'] ?? []) as List<dynamic>;

    return TopReferrer(
      userId: toInt(map['user_id'] ?? map['userId']),
      name: toStr(map['name'], '—'),
      phone: toStr(map['phone']),
      activeCount: toInt(map['active_count'] ?? map['activeCount']),
      status: toStatus(map['status']),
      activeUsers: rawUsers
          .map((e) => ActiveReferredUser.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
