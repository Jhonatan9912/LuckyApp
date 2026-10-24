import 'package:flutter/material.dart';

/// Pantalla cuya librería se importa con `deferred as`: en la web su código
/// se descarga solo al abrirla, así el arranque (login) pesa menos.
/// En Android/iOS la carga es inmediata.
class DeferredScreen extends StatefulWidget {
  const DeferredScreen({
    super.key,
    required this.loadLibrary,
    required this.builder,
  });

  final Future<void> Function() loadLibrary;
  final WidgetBuilder builder;

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late final Future<void> _future = widget.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.builder(context);
        }
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: Center(
            child: snapshot.hasError
                ? const Text(
                    'No se pudo cargar. Revisa tu conexión y recarga la página.',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  )
                : const CircularProgressIndicator(color: Color(0xFFD4AF37)),
          ),
        );
      },
    );
  }
}
