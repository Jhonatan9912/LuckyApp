import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  Future<String> _loadMd() => rootBundle.loadString('assets/legal/terms_es.md');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Términos y Condiciones')),
      body: FutureBuilder<String>(
        future: _loadMd(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return const Center(child: Text('No se pudo cargar el documento.'));
          }
          return Markdown(
            data: snap.data!,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            selectable: true,
            onTapLink: (text, href, title) {
              // Si quieres abrir enlaces externos, puedes usar url_launcher aquí.
            },
          );
        },
      ),
    );
  }
}
