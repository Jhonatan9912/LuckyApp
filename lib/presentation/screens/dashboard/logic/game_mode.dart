// lib/presentation/screens/dashboard/logic/game_mode.dart

enum GameMode {
  digits2,
  digits3,
  digits4,
  quinta, // 4 cifras + extra (1..9)
}

extension GameModeX on GameMode {
  String get apiValue {
    switch (this) {
      case GameMode.digits2:
        return '2';
      case GameMode.digits3:
        return '3';
      case GameMode.digits4:
        return '4';
      case GameMode.quinta:
        return 'quinta';
    }
  }

  int get baseDigits {
    switch (this) {
      case GameMode.digits2:
        return 2;
      case GameMode.digits3:
        return 3;
      case GameMode.digits4:
        return 4;
      case GameMode.quinta:
        return 4;
    }
  }

  bool get hasFifth => this == GameMode.quinta;

  /// True si este modo es completamente gratis (jugar + reservar)
  bool get isFreeMode => this == GameMode.digits2;
}
