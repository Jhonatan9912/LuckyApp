// lib/web/admin/admin_referrals_page.dart
//
// Referidos y pagos: resumen, solicitudes de retiro (pagar / rechazar en lote)
// e historial de pagos con su evidencia.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:base_app/data/api/api_service.dart';
import 'package:base_app/data/models/payout_batch.dart';
import 'package:base_app/data/models/top_referrer.dart';
import 'package:base_app/data/session/session_manager.dart';
import 'package:base_app/domain/models/commission_request.dart';
import 'package:base_app/presentation/screens/admin_dashboard/logic/referrals_controller.dart';

import '../alerts/web_alerts.dart';
import '../shell/web_shell_layout.dart';
import '../theme/web_palette.dart';
import '../widgets/web_ui.dart';
import 'admin_common.dart';

enum _Tab { summary, requests, payouts }

class AdminReferralsPage extends StatefulWidget {
  final ReferralsController ctrl;
  const AdminReferralsPage({super.key, required this.ctrl});

  @override
  State<AdminReferralsPage> createState() => _AdminReferralsPageState();
}

class _AdminReferralsPageState extends State<AdminReferralsPage> {
  _Tab _tab = _Tab.requests;
  final Set<int> _selected = {};

  ReferralsController get c => widget.ctrl;

  String _d(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void initState() {
    super.initState();
    c.load();
    c.loadTop();
    c.loadCommissions(status: 'requested');
    c.loadPayouts();
  }

  double get _selectedTotal => c.commissions
      .where((r) => _selected.contains(r.id))
      .fold(0.0, (a, r) => a + r.amountCop);

  // ───────────── Pagar / rechazar ─────────────

  Future<void> _paySelected() async {
    if (_selected.isEmpty) return;
    final note = TextEditingController();
    final files = <PlatformFile>[];

    final ok = await showWebModal<bool>(
      context,
      title: 'Confirmar pago',
      subtitle: '${_selected.length} solicitudes · ${fmtCop(_selectedTotal)}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: note,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Ej. Transferencia Banco X #123…',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                side: BorderSide(color: WebPalette.gold.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(
                Icons.upload_file_rounded,
                color: WebPalette.goldLight,
              ),
              label: Text(
                'Adjuntar comprobantes',
                style: WebPalette.body(
                  14,
                  weight: FontWeight.w700,
                  color: WebPalette.text,
                ),
              ),
              onPressed: () async {
                final res = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                  withData: kIsWeb,
                );
                if (res == null) return;
                setLocal(
                  () => files.addAll(
                    res.files.where((f) => f.bytes != null || f.path != null),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            for (final f in files)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withValues(alpha: 0.04),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.insert_drive_file_outlined,
                      size: 18,
                      color: WebPalette.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f.name,
                        overflow: TextOverflow.ellipsis,
                        style: WebPalette.body(13.5),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setLocal(() => files.remove(f)),
                    ),
                  ],
                ),
              ),
            ModalActions(
              okText: 'Confirmar pago',
              onOk: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final out = await c.createPayoutBatch(
        requestIds: _selected.toList(),
        note: note.text.trim(),
        files: files,
      );
      setState(_selected.clear);
      await c.loadCommissions(status: 'requested');
      await c.load();
      await c.loadPayouts();
      WebAlerts.toast(
        'Lote #${out?['batch_id'] ?? ''} creado. Las solicitudes quedaron pagadas.',
        title: 'Pago registrado',
        tone: AlertTone.success,
      );
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo crear el pago',
        message: prettyError(e),
        tone: AlertTone.error,
      );
    }
  }

  Future<void> _rejectSelected() async {
    if (_selected.isEmpty || c.rejecting) return;
    final reason = TextEditingController();
    final ok = await showWebModal<bool>(
      context,
      title: 'Rechazar solicitudes',
      subtitle:
          'El usuario recibirá el motivo y el dinero volverá a "Disponible".',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: reason,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Motivo del rechazo',
              hintText: 'Ej. Número de cuenta inválido',
            ),
          ),
          ModalActions(
            okText: 'Rechazar',
            danger: true,
            onOk: () {
              if (reason.text.trim().isEmpty) {
                WebAlerts.toast(
                  'Escribe el motivo del rechazo.',
                  tone: AlertTone.warning,
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await c.rejectSelected(_selected.toList(), reason.text.trim());
      setState(_selected.clear);
      await c.loadCommissions(status: 'requested');
      await c.load();
      WebAlerts.toast('Solicitudes rechazadas.', tone: AlertTone.success);
    } catch (e) {
      await WebAlerts.dialog(
        title: 'No se pudo rechazar',
        message: prettyError(e),
        tone: AlertTone.error,
      );
    }
  }

  Future<void> _openBatch(PayoutBatch b) async {
    await showWebModal(
      context,
      title: 'Pago ${b.code ?? '#${b.id}'}',
      subtitle: '${_d(b.createdAt)} · ${fmtCop(b.totalCop)}',
      maxWidth: 680,
      builder: (_) => _BatchDetails(ctrl: c, batchId: b.id),
    );
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => WebPage(
        children: [
          ResponsiveGrid(
            minItemWidth: 200,
            children: [
              StatTile(
                label: 'Referidos',
                value: c.totalLabel,
                icon: Icons.groups_2_outlined,
              ),
              StatTile(
                label: 'Activos',
                value: c.activeLabel,
                icon: Icons.verified_outlined,
                color: WebPalette.emerald,
              ),
              StatTile(
                label: 'Solicitudes pendientes',
                value: '${c.pendingCommissionsCount}',
                icon: Icons.pending_actions_outlined,
                color: WebPalette.amber,
              ),
              StatTile(
                label: 'Por pagar',
                value: c.pendingLabel,
                icon: Icons.hourglass_top_rounded,
                color: WebPalette.amber,
              ),
              StatTile(
                label: 'Pagado',
                value: c.paidLabel,
                icon: Icons.payments_outlined,
                color: WebPalette.emerald,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: WebSegmented<_Tab>(
              options: const [
                (_Tab.requests, 'Solicitudes de retiro'),
                (_Tab.payouts, 'Pagos realizados'),
                (_Tab.summary, 'Top referidores'),
              ],
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
          const SizedBox(height: 18),
          switch (_tab) {
            _Tab.requests => _requests(),
            _Tab.payouts => _payouts(),
            _Tab.summary => _top(),
          },
        ],
      ),
    );
  }

  Widget _requests() {
    final rows = c.commissions;
    return WebPanel(
      title: 'Solicitudes de retiro',
      subtitle: _selected.isEmpty
          ? 'Selecciona las solicitudes que vas a pagar o rechazar'
          : '${_selected.length} seleccionadas · ${fmtCop(_selectedTotal)}',
      icon: Icons.request_page_outlined,
      actions: [
        WebIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Actualizar',
          onPressed: () => c.loadCommissions(status: 'requested'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: WebPalette.gold,
                  foregroundColor: const Color(0xFF1A1300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _selected.isEmpty || c.paying ? null : _paySelected,
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: Text(
                  'Pagar seleccionadas',
                  style: WebPalette.body(
                    14,
                    weight: FontWeight.w800,
                    color: const Color(0xFF1A1300),
                  ),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: WebPalette.danger,
                  side: BorderSide(
                    color: WebPalette.danger.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _selected.isEmpty || c.rejecting
                    ? null
                    : _rejectSelected,
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Rechazar'),
              ),
              if (rows.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == rows.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(rows.map((r) => r.id));
                    }
                  }),
                  child: Text(
                    _selected.length == rows.length
                        ? 'Quitar selección'
                        : 'Seleccionar todas',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (c.loadingCommissions)
            const TableSkeleton(rows: 4)
          else if (rows.isEmpty)
            const EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'No hay solicitudes pendientes',
              message: 'Cuando un usuario pida un retiro aparecerá aquí.',
            )
          else
            WebTable<CommissionRequest>(
              rows: rows,
              isSelected: (r) => _selected.contains(r.id),
              onRowTap: (r) => setState(
                () => _selected.contains(r.id)
                    ? _selected.remove(r.id)
                    : _selected.add(r.id),
              ),
              mobileTitle: (r) => Text(
                r.userName,
                style: WebPalette.display(15, weight: FontWeight.w700),
              ),
              columns: [
                WebColumn(
                  '',
                  (r) => Checkbox(
                    value: _selected.contains(r.id),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _selected.add(r.id)
                          : _selected.remove(r.id),
                    ),
                  ),
                  flex: 1,
                ),
                WebColumn(
                  'Usuario',
                  (r) => CellText(r.userName, strong: true),
                  flex: 4,
                ),
                WebColumn('Solicitud', (r) => CellText('#${r.id}'), flex: 2),
                WebColumn('Fecha', (r) => CellText(_d(r.createdAt)), flex: 2),
                WebColumn(
                  'Monto',
                  (r) => CellText(fmtCop(r.amountCop), mono: true),
                  flex: 2,
                  numeric: true,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _payouts() {
    final rows = c.payouts;
    return WebPanel(
      title: 'Pagos realizados',
      subtitle: 'Lotes de pago con su comprobante',
      icon: Icons.receipt_long_outlined,
      actions: [
        WebIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Actualizar',
          onPressed: c.loadPayouts,
        ),
      ],
      child: c.loadingPayouts
          ? const TableSkeleton(rows: 4)
          : rows.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Aún no hay pagos registrados',
            )
          : WebTable<PayoutBatch>(
              rows: rows,
              onRowTap: _openBatch,
              mobileTitle: (b) => Text(
                b.code ?? 'Lote #${b.id}',
                style: WebPalette.display(15, weight: FontWeight.w700),
              ),
              trailing: (b) => TextButton(
                onPressed: () => _openBatch(b),
                child: const Text('Ver detalle'),
              ),
              columns: [
                WebColumn(
                  'Lote',
                  (b) => CellText(b.code ?? '#${b.id}', strong: true),
                  flex: 2,
                ),
                WebColumn('Fecha', (b) => CellText(_d(b.createdAt)), flex: 2),
                WebColumn(
                  'Beneficiario',
                  (b) => CellText(
                    b.items == 1
                        ? (b.firstUserName ?? '')
                        : '${b.items} usuarios',
                  ),
                  flex: 3,
                ),
                WebColumn(
                  'Comprobante',
                  (b) => b.hasFiles
                      ? const StatusChip(
                          label: 'Adjunto',
                          color: WebPalette.emerald,
                          icon: Icons.attach_file_rounded,
                        )
                      : const StatusChip(
                          label: 'Sin archivo',
                          color: WebPalette.textFaint,
                        ),
                  flex: 2,
                ),
                WebColumn(
                  'Total',
                  (b) => CellText(fmtCop(b.totalCop), mono: true),
                  flex: 2,
                  numeric: true,
                ),
              ],
            ),
    );
  }

  Widget _top() {
    final rows = c.top;
    return WebPanel(
      title: 'Top referidores',
      subtitle: 'Usuarios con más referidos activos',
      icon: Icons.leaderboard_outlined,
      child: rows.isEmpty
          ? const EmptyState(
              icon: Icons.leaderboard_outlined,
              title: 'Sin datos todavía',
            )
          : WebTable<TopReferrer>(
              rows: rows,
              mobileTitle: (t) => Text(
                t.name,
                style: WebPalette.display(15, weight: FontWeight.w700),
              ),
              columns: [
                WebColumn(
                  '#',
                  (t) => CellText('${rows.indexOf(t) + 1}', mono: true),
                  flex: 1,
                ),
                WebColumn(
                  'Nombre',
                  (t) => CellText(t.name, strong: true),
                  flex: 4,
                ),
                WebColumn('Celular', (t) => CellText(t.phone), flex: 3),
                WebColumn(
                  'Referidos activos',
                  (t) => CellText('${t.activeCount}', strong: true),
                  flex: 2,
                ),
                WebColumn(
                  'Plan',
                  (t) => t.status == 'PRO'
                      ? const StatusChip(
                          label: 'PRO',
                          color: WebPalette.goldLight,
                        )
                      : const StatusChip(
                          label: 'FREE',
                          color: WebPalette.textFaint,
                        ),
                  flex: 2,
                ),
              ],
            ),
    );
  }
}

class _BatchDetails extends StatefulWidget {
  final ReferralsController ctrl;
  final int batchId;
  const _BatchDetails({required this.ctrl, required this.batchId});

  @override
  State<_BatchDetails> createState() => _BatchDetailsState();
}

class _BatchDetailsState extends State<_BatchDetails> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.loadPayoutBatchDetails(widget.batchId, force: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ctrl,
      builder: (context, _) {
        final c = widget.ctrl;
        final d = c.currentBatchDetails;
        if (c.loadingBatchDetails ||
            d == null ||
            d.batch.id != widget.batchId) {
          if (c.batchDetailsError != null) {
            return EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No se pudo cargar',
              message: c.batchDetailsError,
            );
          }
          return const TableSkeleton(rows: 3);
        }
        final base = ApiService.defaultBaseUrl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((d.batch.note ?? '').isNotEmpty) ...[
              Text(
                'Nota',
                style: WebPalette.body(12.5, color: WebPalette.textFaint),
              ),
              const SizedBox(height: 4),
              Text(
                d.batch.note!,
                style: WebPalette.body(14, color: WebPalette.text),
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'Solicitudes pagadas',
              style: WebPalette.display(15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (final r in d.requests)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(color: WebPalette.glassBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (r.userName ?? '').isEmpty
                                ? 'Usuario #${r.userId ?? r.id}'
                                : r.userName!,
                            style: WebPalette.body(
                              14,
                              weight: FontWeight.w700,
                              color: WebPalette.text,
                            ),
                          ),
                          Text(
                            [
                              if ((r.userCode ?? '').isNotEmpty)
                                'Código ${r.userCode}',
                              if ((r.documentId ?? '').isNotEmpty)
                                'CC ${r.documentId}',
                            ].join(' · '),
                            style: WebPalette.body(12.5),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      fmtCop(r.amountCop),
                      style: WebPalette.display(
                        15,
                        weight: FontWeight.w700,
                        color: WebPalette.goldLight,
                      ),
                    ),
                  ],
                ),
              ),
            if (d.files.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Comprobantes',
                style: WebPalette.display(15, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final f in d.files)
                    _AuthImage(
                      url: f.url.startsWith('http') ? f.url : '$base${f.url}',
                      name: f.name,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Imagen protegida con token (comprobantes).
class _AuthImage extends StatefulWidget {
  final String url;
  final String name;
  const _AuthImage({required this.url, required this.name});

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await SessionManager().getToken();
      final res = await http.get(
        Uri.parse(widget.url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (!mounted) return;
      setState(
        () => res.statusCode < 300 ? _bytes = res.bodyBytes : _error = true,
      );
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_error) {
      child = const Icon(
        Icons.broken_image_outlined,
        color: WebPalette.textFaint,
      );
    } else if (_bytes == null) {
      child = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      child = Image.memory(_bytes!, fit: BoxFit.cover, width: 200, height: 150);
    }
    return GestureDetector(
      onTap: _bytes == null
          ? null
          : () => showDialog(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.85),
              builder: (ctx) => GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Center(
                  child: InteractiveViewer(child: Image.memory(_bytes!)),
                ),
              ),
            ),
      child: MouseRegion(
        cursor: _bytes == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.zoomIn,
        child: Container(
          width: 200,
          height: 150,
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(color: WebPalette.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}
