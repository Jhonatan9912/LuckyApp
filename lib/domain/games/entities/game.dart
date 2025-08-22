// game.dart
class Game {
  final int id;
  Game(this.id);
}

// generated_selection.dart
class GeneratedSelection {
  final int gameId;
  final List<int> numbers; // 5 números 0..999
  const GeneratedSelection({required this.gameId, required this.numbers});
}
