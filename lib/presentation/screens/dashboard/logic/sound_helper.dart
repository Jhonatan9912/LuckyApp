import 'package:audioplayers/audioplayers.dart';
import 'package:logging/logging.dart'; // ✅ nuevo

class SoundHelper {
  static final AudioPlayer _player = AudioPlayer();
  static final Logger _logger = Logger('SoundHelper'); // ✅ nuevo

  static Future<void> playPopSound() async {
    try {
      await _player.stop(); // 🔁 Detiene cualquier reproducción anterior
      await _player.play(AssetSource('sounds/pop.mp3'));
      _logger.info('Sonido reproducido correctamente');
    } catch (e) {
      _logger.severe('Error al reproducir sonido: $e');
    }
  }
}
