// lib/data/models/payout_batch_detail.dart
class PayoutBatchHeader {
  final int id;
  final DateTime? createdAt;
  final DateTime? confirmedAt;
  final String currency;   // alias de currency_code
  final int totalCop;      // entero sin decimales
  final int items;         // cantidad de requests
  final String? status;
  final String? note;
  final int? createdBy;

  const PayoutBatchHeader({
    required this.id,
    required this.createdAt,
    required this.currency,
    required this.totalCop,
    required this.items,
    this.confirmedAt,
    this.status,
    this.note,
    this.createdBy,
  });

  factory PayoutBatchHeader.fromJson(Map<String, dynamic> j) {
    // Soporta nuevo (item.*) y viejo (batch.*)
    final currency = (j['currency'] ?? j['currency_code'] ?? 'COP') as String;

    // total micros → totalCop si viene en nuevo contrato
    final micros = _toInt(j['total_micros'] ?? j['total_amount_micros']);
    final totalCop =
        (micros != 0) ? _microsToCopInt(micros) : _toInt(j['total_cop']);

    final items =
        _toInt(j['total_requests'] ?? j['requests_count'] ?? j['items']);

    return PayoutBatchHeader(
      id: _toInt(j['id']),
      createdAt: _parseDate(j['created_at']),
      confirmedAt: _parseDate(j['confirmed_at']),
      currency: currency,
      totalCop: totalCop,
      items: items,
      status: j['status'] as String?,
      note: j['note'] as String?,
      createdBy: j['created_by'] == null ? null : _toInt(j['created_by']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt?.toUtc().toIso8601String(),
        'confirmed_at': confirmedAt?.toUtc().toIso8601String(),
        'currency': currency,
        'total_cop': totalCop,
        'items': items,
        'status': status,
        'note': note,
        'created_by': createdBy,
      };

  String get totalCopLabel => _fmtCop(totalCop);

  @override
  String toString() =>
      'PayoutBatchHeader(id: $id, createdAt: $createdAt, currency: $currency, totalCop: $totalCop, items: $items, status: $status)';
}

/// Ítem (solicitud) dentro del lote.
/// En nuevo contrato viene como `items[]` con amount_micros.
class PayoutRequestEntry {
  final int id;           // request_id
  final int? userId;
  final String? userName; // opcional si tu backend no lo envía
  final String? userCode; // opcional
  final String? documentId;
  final int amountCop;    // derivado de micros si hace falta
  final DateTime? createdAt;
  final String? currencyCode;
  final String? status;

  const PayoutRequestEntry({
    required this.id,
    required this.userId,
    required this.amountCop,
    this.userName,
    this.userCode,
    this.documentId,
    this.createdAt,
    this.currencyCode,
    this.status,
  });

  factory PayoutRequestEntry.fromJson(Map<String, dynamic> j) {
    // id puede venir como id o request_id
    final rid = _toInt(j['request_id'] ?? j['id']);
    // micros (nuevo) → COP; si no, amount_cop (viejo)
    final micros = _toInt(j['amount_micros']);
    final amountCop =
        (micros != 0) ? _microsToCopInt(micros) : _toInt(j['amount_cop']);

    return PayoutRequestEntry(
      id: rid,
      userId: j['user_id'] == null ? null : _toInt(j['user_id']),
      amountCop: amountCop,
      createdAt: _parseDate(j['created_at']),
      currencyCode: (j['currency'] ?? j['currency_code']) as String?,
      status: j['status'] as String?,
      // Los siguientes campos son opcionales/legacy
      userName: j['user_name'] as String?,
      userCode: j['user_code'] as String?,
      documentId: j['document_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'request_id': id,
        'user_id': userId,
        'amount_cop': amountCop,
        'created_at': createdAt?.toUtc().toIso8601String(),
        'currency_code': currencyCode,
        'status': status,
        'user_name': userName,
        'user_code': userCode,
        'document_id': documentId,
      };

  String get amountLabel => _fmtCop(amountCop);

  @override
  String toString() =>
      'PayoutRequestEntry(id: $id, userId: $userId, amountCop: $amountCop, status: $status)';
}

/// Archivo de evidencia (con URL servida por el backend).
class PayoutEvidenceFile {
  final int id;
  final String name;     // file_name|name
  final String url;      // url|download_url
  final String? mimeType;
  final int sizeBytes;

  const PayoutEvidenceFile({
    required this.id,
    required this.name,
    required this.url,
    required this.sizeBytes,
    this.mimeType,
  });

  factory PayoutEvidenceFile.fromJson(Map<String, dynamic> j) {
    return PayoutEvidenceFile(
      id: _toInt(j['id']),
      name: (j['file_name'] ?? j['name'] ?? 'evidence') as String,
      url: (j['url'] ?? j['download_url'] ?? '') as String,
      sizeBytes: _toInt(j['size_bytes']),
      mimeType: j['mime_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'size_bytes': sizeBytes,
        'mime_type': mimeType,
      };

  @override
  String toString() => 'PayoutEvidenceFile(id: $id, name: $name, url: $url)';
}

/// Contenedor final del detalle del lote.
/// Si viene formato nuevo: toma `json['item']`.
/// Si viene antiguo: usa `batch/requests/files`.
class PayoutBatchDetails {
  final PayoutBatchHeader batch;
  final List<PayoutRequestEntry> requests;
  final List<PayoutEvidenceFile> files;

  const PayoutBatchDetails({
    required this.batch,
    required this.requests,
    required this.files,
  });

  factory PayoutBatchDetails.fromJson(Map<String, dynamic> j) {
    // Detectar forma
    final Map<String, dynamic> root =
        (j['item'] is Map) ? Map<String, dynamic>.from(j['item'] as Map) : j;

    // Si es forma antigua, reorganizamos a la forma nueva
    if (root.containsKey('batch') || root.containsKey('requests')) {
      final b = Map<String, dynamic>.from((root['batch'] ?? const {}) as Map);
      final reqs = (root['requests'] as List<dynamic>? ?? const [])
          .map((e) => PayoutRequestEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
      final fs = (root['files'] as List<dynamic>? ?? const [])
          .map((e) => PayoutEvidenceFile.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();

      return PayoutBatchDetails(
        batch: PayoutBatchHeader.fromJson(b),
        requests: reqs,
        files: fs,
      );
    }

    // Forma nueva: header dentro del mismo objeto + arrays items/files
    final header = PayoutBatchHeader.fromJson(root);

    final reqs = (root['items'] as List<dynamic>? ?? const [])
        .map((e) => PayoutRequestEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();

    final fs = (root['files'] as List<dynamic>? ?? const [])
        .map((e) => PayoutEvidenceFile.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();

    return PayoutBatchDetails(
      batch: header,
      requests: reqs,
      files: fs,
    );
  }

  Map<String, dynamic> toJson() => {
        'batch': batch.toJson(),
        'requests': requests.map((e) => e.toJson()).toList(),
        'files': files.map((e) => e.toJson()).toList(),
      };

  bool get hasFiles => files.isNotEmpty;

  @override
  String toString() =>
      'PayoutBatchDetails(batch: $batch, requests: ${requests.length}, files: ${files.length})';
}

/// =====================
/// Helpers compartidos
/// =====================
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

int _microsToCopInt(int micros) => micros ~/ 1000000;

/// Formatea COP sin decimales: 45000 -> "$45.000"
String _fmtCop(int value) {
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idxFromRight = s.length - i;
    buf.write(s[i]);
    final isThousandSepSpot = idxFromRight > 1 && (idxFromRight - 1) % 3 == 0;
    if (isThousandSepSpot) buf.write('.');
  }
  final sign = value < 0 ? '-' : '';
  return '$sign\$${buf.toString()}';
}
