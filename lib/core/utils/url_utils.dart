// lib/core/utils/url_utils.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlUtils {
  static Future<void> openExternal(
    BuildContext context, {
    required String url,
  }) async {
    final uri = Uri.parse(url);

    // helper local sin prefijo _
    Future<bool> tryMode(LaunchMode mode) async {
      try {
        return await launchUrl(uri, mode: mode);
      } catch (_) {
        return false;
      }
    }

    // 1) App externa (WhatsApp/Chrome)
    if (await tryMode(LaunchMode.externalApplication)) return;

    // 2) In-app browser (Custom Tabs / SFSafariViewController)
    if (await tryMode(LaunchMode.inAppBrowserView)) return;

    // 3) Último recurso: webview embebido
    if (await tryMode(LaunchMode.inAppWebView)) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude abrir el enlace: $url')),
      );
    }
  }
}
