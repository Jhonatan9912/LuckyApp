// lib/web/screens/web_legal_screen.dart
//
// Documentos legales (términos, tratamiento de datos) con diseño web.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/web_palette.dart';
import '../theme/web_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/web_ui.dart';

class WebLegalScreen extends StatelessWidget {
  final String title;
  final String asset;
  const WebLegalScreen({super.key, required this.title, required this.asset});

  @override
  Widget build(BuildContext context) {
    final mobile = WebBreakpoints.isMobile(context);
    return Theme(
      data: buildWebTheme(),
      child: Scaffold(
        backgroundColor: WebPalette.bg,
        body: AuroraBackground(
          showGrid: false,
          animate: false,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 8 : 32,
                    16,
                    mobile ? 8 : 32,
                    8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Volver',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: WebPalette.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: WebPalette.display(
                            mobile ? 19 : 24,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<String>(
                    future: rootBundle.loadString(asset),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snap.hasData) {
                        return const EmptyState(
                          icon: Icons.description_outlined,
                          title: 'No se pudo cargar el documento',
                        );
                      }
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          mobile ? 14 : 32,
                          8,
                          mobile ? 14 : 32,
                          40,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: WebPanel(
                              padding: EdgeInsets.all(mobile ? 18 : 36),
                              child: MarkdownBody(
                                data: snap.data!,
                                selectable: true,
                                styleSheet: MarkdownStyleSheet(
                                  p: WebPalette.body(15, height: 1.7),
                                  h1: WebPalette.display(
                                    26,
                                    weight: FontWeight.w800,
                                  ),
                                  h2: WebPalette.display(
                                    20,
                                    weight: FontWeight.w700,
                                  ),
                                  h3: WebPalette.display(
                                    17,
                                    weight: FontWeight.w700,
                                  ),
                                  listBullet: WebPalette.body(
                                    15,
                                    color: WebPalette.goldLight,
                                  ),
                                  strong: WebPalette.body(
                                    15,
                                    weight: FontWeight.w700,
                                    color: WebPalette.text,
                                  ),
                                  blockSpacing: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
