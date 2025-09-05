import 'package:base_app/data/datasources/payouts_api.dart';
import 'package:base_app/domain/models/payout_request.dart';

class PayoutsRepository {
  final PayoutsApi api;

  PayoutsRepository(this.api);

  Future<void> create(PayoutRequestInput input) => api.createPayoutRequest(input);
}
