import 'package:base_app/data/api/games_api.dart';

class CommitSelection {
  final GamesApi api;
  CommitSelection(this.api);

  Future<Map<String, dynamic>> call({
    required int gameId,
    required List<int> numbers,
    String? token,
    int? xUserId, // 👈 renombrado para coincidir con GamesApi.commit
  }) {
    return api.commit(
      gameId: gameId,
      numbers: numbers,
      token: token,
      xUserId: xUserId, // 👈 actualizado
    );
  }
}
