import 'dart:typed_data';

/// No disponible fuera de web.
void downloadBytesInBrowser(
  Uint8List bytes, {
  required String fileName,
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('downloadBytesInBrowser solo está disponible en web');
}
