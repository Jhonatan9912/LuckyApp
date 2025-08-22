import 'package:base_app/data/api/admin_api.dart';

class AdminRepository {
  final AdminApi api;
  AdminRepository({required this.api});

  Future<Map<String, dynamic>> getSummary() => api.fetchDashboardSummary();
}