import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart'; // ✅ nuevo

class SoundHelper {
  static final AudioPlayer _player = AudioPlayer();
  static final Logger _logger = Logger('SoundHelper'); // ✅ nuevo

  static Future<void> playPopSound() async {
    // En web el navegador puede dejar la reproducción pendiente; no se espera
    // para no bloquear la animación de reserva.
    if (kIsWeb) {
      unawaited(
        _player
            .play(AssetSource('sounds/pop.mp3'))
            .timeout(const Duration(seconds: 2))
            .catchError((Object e) => _logger.warning('Sonido web: $e')),
      );
      return;
    }
    try {
      await _player.stop(); // 🔁 Detiene cualquier reproducción anterior
      await _player.play(AssetSource('sounds/pop.mp3'));
      _logger.info('Sonido reproducido correctamente');
    } catch (e) {
      _logger.severe('Error al reproducir sonido: $e');
    }
  }
}
