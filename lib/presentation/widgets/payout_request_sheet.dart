import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:base_app/web/widgets/web_ui.dart' show showWebModal;
// lib/presentation/widgets/payout_request_sheet.dart
import 'package:flutter/material.dart';
import 'package:base_app/core/ui/dialogs.dart' show AppSnackBars;
import 'package:provider/provider.dart';

import 'package:base_app/domain/models/bank.dart';
import 'package:base_app/domain/models/payout_request.dart';
import 'package:base_app/presentation/providers/payouts_provider.dart';
import 'package:base_app/presentation/providers/referral_provider.dart';
import 'package:flutter/services.dart';

class _PayoutOption {
  final String label; // Texto visible
  final String
  bankCode; // Código (DB) si es banco; si no, el code del item SEDPE
  final String entityType; // 'BANK' | 'CF' | 'SEDPE'
  final String accountType; // 'bank' | 'nequi' | 'daviplata' | 'other'

  const _PayoutOption({
    required this.label,
    required this.bankCode,
    required this.entityType,
    required this.accountType,
  });

  @override
  String toString() => label;
}

Future<bool?> showPayoutRequestSheet(BuildContext context) {
  // En web se abre como modal centrado.
  if (kIsWeb) {
    return showWebModal<bool>(
      context,
      title: 'Solicitar retiro',
      subtitle: 'Recibe tus comisiones en tu cuenta bancaria o billetera.',
      builder: (_) => const _PayoutRequestForm(),
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _PayoutRequestForm(),
  );
}

class _PayoutRequestForm extends StatefulWidget {
  const _PayoutRequestForm();

  @override
  State<_PayoutRequestForm> createState() => _PayoutRequestFormState();
}

class _PayoutRequestFormState extends State<_PayoutRequestForm> {
  final _formKey = GlobalKey<FormState>();

  // Selección por código (estable)
  String? _selectedCode;
  String? _accountKind; // 'savings' | 'checking' (solo bancos)
  final _accountNumberCtrl = TextEditingController();
  final _observationsCtrl = TextEditingController();
  // lookup por código
  Map<String, _PayoutOption> _byCode = const {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      // 🔹 limpia errores previos del provider
      context.read<PayoutsProvider>().clearErrors();
      // 🔹 carga bancos
      context.read<PayoutsProvider>().loadBanks(force: true);
    });
  }

  @override
  void dispose() {
    _accountNumberCtrl.dispose();
    _observationsCtrl.dispose();
    super.dispose();
  }

  // Normaliza nombre para deduplicar (sin tildes, minúsculas)
  String _norm(String s) {
    const accentsMap = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ä': 'a',
      'ë': 'e',
      'ï': 'i',
      'ö': 'o',
      'ü': 'u',
      'Á': 'a',
      'É': 'e',
      'Í': 'i',
      'Ó': 'o',
      'Ú': 'u',
      'Ä': 'a',
      'Ë': 'e',
      'Ï': 'i',
      'Ö': 'o',
      'Ü': 'u',
      'ñ': 'n',
      'Ñ': 'n',
    };
    final sb = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      sb.write(accentsMap[ch] ?? ch);
    }
    return sb.toString().toLowerCase().trim();
  }

  // Prioridad: BANK > CF > SEDPE
  int _priority(String et) {
    switch (et) {
      case 'BANK':
        return 3;
      case 'CF':
        return 2;
      case 'SEDPE':
        return 1;
      default:
        return 0;
    }
  }

  // Construye lista mezclada (BANK/CF/SEDPE), deduplicada por nombre normalizado,
  // conservando el de mayor prioridad.
  List<_PayoutOption> _buildOptionsFromDb(List<Bank> banks) {
    final bestByName = <String, _PayoutOption>{};

    for (final b in banks) {
      if (!b.active) continue;

      final et = b.entityType.toUpperCase();
      if (et != 'BANK' && et != 'CF' && et != 'SEDPE') continue;

      final code = b.code.trim();
      if (code.isEmpty) continue;

      final label = (b.shortName.isNotEmpty ? b.shortName : b.name).trim();
      if (label.isEmpty) continue;

      String accountType;
      final codeUp = code.toUpperCase();
      if (et == 'BANK' || et == 'CF') {
        accountType = 'bank';
      } else if (et == 'SEDPE' && codeUp.startsWith('NEQUI')) {
        accountType = 'nequi';
      } else if (et == 'SEDPE' && codeUp.startsWith('DAVIPLATA')) {
        accountType = 'daviplata';
      } else {
        accountType = 'other';
      }

      final opt = _PayoutOption(
        label: label,
        bankCode: code,
        entityType: et,
        accountType: accountType,
      );

      final key = _norm(label);
      final prev = bestByName[key];
      if (prev == null || _priority(et) > _priority(prev.entityType)) {
        bestByName[key] = opt;
      }
    }

    final opts = bestByName.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    _byCode = {for (final o in opts) o.bankCode: o};
    return opts;
  }

  bool get _isBank {
    final code = _selectedCode;
    if (code == null) return false;
    final opt = _byCode[code];
    if (opt == null) return false;
    return opt.accountType == 'bank';
  }

  String get _numberLabel => _isBank ? 'Número de cuenta' : 'Número de celular';

  String? _validateNumber(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Este campo es obligatorio';

    if (_isBank) {
      if (!RegExp(r'^\d{5,}$').hasMatch(s)) {
        return 'Sólo números (mín. 5 dígitos)';
      }
    } else {
      if (!RegExp(r'^\d{10}$').hasMatch(s)) {
        return 'Ingresa un celular de 10 dígitos';
      }
    }

    return null;
  }

  Future<void> _showSuccessSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, size: 64),
              const SizedBox(height: 12),
              const Text(
                '¡Solicitud enviada!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isBank
                    ? 'Procesaremos tu retiro a la cuenta seleccionada.'
                    : 'Procesaremos tu retiro al número de celular indicado.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Form(
            key: _formKey,
            child: Consumer<PayoutsProvider>(
              builder: (_, p, __) {
                if (p.loadingBanks) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SizedBox(height: 8),
                      Text(
                        'Solicitar retiro',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      Center(child: CircularProgressIndicator()),
                    ],
                  );
                }

                if (p.banksError != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'Solicitar retiro',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Error cargando bancos: ${p.banksError}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  );
                }

                if (p.banks.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SizedBox(height: 8),
                      Text(
                        'Solicitar retiro',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text('No hay entidades disponibles.'),
                    ],
                  );
                }

                final options = _buildOptionsFromDb(p.banks);

                // Re-sincroniza selección
                if (_selectedCode == null ||
                    !_byCode.containsKey(_selectedCode)) {
                  _selectedCode = options.isNotEmpty
                      ? options.first.bankCode
                      : null;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitar retiro',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selecciona el banco o billetera y completa los datos.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),

                    // Dropdown por código (mezcla BANK/CF/SEDPE deduplicado)
                    DropdownButtonFormField<String>(
                      value: _selectedCode,
                      decoration: const InputDecoration(
                        labelText: 'Banco o billetera',
                        border: OutlineInputBorder(),
                      ),
                      items: options
                          .map(
                            (opt) => DropdownMenuItem<String>(
                              value: opt.bankCode,
                              child: Text(
                                opt.label +
                                    (opt.entityType == 'CF' ? ' (CF)' : ''),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedCode = v;
                          if (!_isBank) _accountKind = null;
                        });
                      },
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Selecciona una opción'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // Tipo de cuenta SOLO si es BANK/CF
                    if (_isBank) ...[
                      DropdownButtonFormField<String>(
                        value: _accountKind,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de cuenta',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'savings',
                            child: Text('Ahorros'),
                          ),
                          DropdownMenuItem(
                            value: 'checking',
                            child: Text('Corriente'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _accountKind = v),
                        validator: (v) {
                          if (_isBank && (v == null || v.isEmpty)) {
                            return 'Selecciona ahorros o corriente';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Número (cuenta o celular según selección)
                    TextFormField(
                      controller: _accountNumberCtrl,
                      decoration: InputDecoration(
                        labelText: _numberLabel,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.numbers),
                        counterText: '', // oculta el contador del maxLength
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        // límite: 10 para celular, más largo para cuentas bancarias
                        if (_isBank)
                          LengthLimitingTextInputFormatter(20)
                        else
                          LengthLimitingTextInputFormatter(10),
                      ],
                      validator: _validateNumber,
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _observationsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones (opcional)',
                        hintText: 'Ej: Titular diferente, instrucciones, etc.',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      maxLength: 500,
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: p.submitting
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) return;
                                if (_selectedCode == null) return;

                                final opt = _byCode[_selectedCode!]!;
                                final input = PayoutRequestInput(
                                  accountType: opt.accountType,
                                  accountNumber: _accountNumberCtrl.text.trim(),
                                  accountKind: _isBank ? _accountKind : null,
                                  bankCode: _isBank ? opt.bankCode : null,
                                  observations:
                                      _observationsCtrl.text.trim().isEmpty
                                      ? null
                                      : _observationsCtrl.text.trim(),
                                );

                                // 👇 Captura dependencias de context ANTES de los awaits
                                final referrals = context
                                    .read<ReferralProvider>();
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                final focusScope = FocusScope.of(context);
                                // Bloquea el envío si ya no cumple el mínimo de $100.000 (por carrera o refresh)
                                if (!referrals.canWithdraw) {
                                  messenger.showAppSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Tu saldo disponible aún no alcanza \$100.000',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                // 1) Submit
                                final ok = await p.submit(input);
                                if (!mounted) return;

                                if (ok) {
                                  // 2) Refrescar saldos usando la ref capturada (sin context)
                                  await referrals.load(refresh: true);
                                  if (!mounted) return;

                                  // 3) Usar las refs capturadas (sin context)
                                  focusScope.unfocus();

                                  // Puedes seguir usando tu helper, pasando el contexto del navigator
                                  await _showSuccessSheet(navigator.context);
                                  if (!mounted) return;

                                  navigator.pop(true);
                                } else {
                                  if (!mounted) return;
                                  messenger.showAppSnackBar(
                                    SnackBar(
                                      content: Text(
                                        p.submitError ??
                                            'No se pudo enviar la solicitud',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.send),
                        label: p.submitting
                            ? const Text('Enviando...')
                            : const Text('Enviar solicitud'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
