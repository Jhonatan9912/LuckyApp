import 'package:base_app/data/api/games_api.dart';
import 'package:base_app/domain/games/entities/generated_selection.dart';

class GenerateSelection {
  final GamesApi api;
  GenerateSelection(this.api);

  Future<GeneratedSelection> call({String? token, int? xUserId}) async {
    final res = await api.generate(token: token, xUserId: xUserId);
    if (res['ok'] != true) {
      throw Exception(res['message'] ?? 'No se pudieron generar números');
    }
    final data = (res['data'] as Map<String, dynamic>? ?? {});
    final gameId = (data['game_id'] as num).toInt();
    final nums = (data['numbers'] as List)
        .map((e) => int.parse(e.toString()))
        .toList();
    return GeneratedSelection(gameId: gameId, numbers: nums);
    }
}
