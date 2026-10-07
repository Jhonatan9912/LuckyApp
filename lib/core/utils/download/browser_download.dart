// lib/core/utils/download/browser_download.dart
//
// Descarga de archivos en el navegador (solo web).
// En móvil se usa el flujo nativo (path_provider + open_filex / share_plus).
export 'browser_download_stub.dart'
    if (dart.library.js_interop) 'browser_download_web.dart';
