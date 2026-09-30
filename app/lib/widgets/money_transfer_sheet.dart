import 'package:flutter/material.dart';

import '../models/settlement_balance.dart';
import '../models/transaction_summary.dart';
import '../services/household_repository.dart';
import '../utils/formato.dart';

/// Enseña cómo van las cuentas y deja apuntar dinero que pasa de uno a otro,
/// tanto para saldar una deuda como para ayudar al otro cuando lo necesita:
/// por dentro es lo mismo, quien pone el dinero queda a favor.
/// Devuelve `true` si se ha guardado algo.
///
/// El saldo se pide antes de abrir la hoja, igual que las categorías en el
/// resto de formularios: así se abre con el número ya puesto y no con un
/// hueco que se rellena a medio camino.
Future<bool> showMoneyTransferSheet(BuildContext context, {required HouseholdRepository repository}) async {
  final saldo = await repository.loadBalance();
  if (!context.mounted) return false;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _SettleDebtSheet(repository: repository, saldo: saldo),
  );
  return saved ?? false;
}

class _SettleDebtSheet extends StatefulWidget {
  const _SettleDebtSheet({required this.repository, required this.saldo});

  final HouseholdRepository repository;
  final SettlementBalance saldo;

  @override
  State<_SettleDebtSheet> createState() => _SettleDebtSheetState();
}

class _SettleDebtSheetState extends State<_SettleDebtSheet> {
  /// Quien pone el dinero: por defecto, quien debe. Lo más habitual es saldar
  /// en la dirección que marca el saldo, así que ya viene elegido.
  late String _de = widget.saldo.deudor;

  /// El importe viene relleno con la deuda entera, que es el caso de siempre;
  /// para una devolución parcial basta con corregirlo.
  late final _importeController = TextEditingController(
    text: widget.saldo.saldado ? null : widget.saldo.importe.toStringAsFixed(2),
  )..addListener(() => setState(() {}));

  final _notaController = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _importeController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  String get _para => _de == personaA ? personaB : personaA;

  /// Si este dinero baja una deuda que ya había, o si la crea porque lo pone
  /// quien no debía nada. No cambia las cuentas, solo cómo se lee luego.
  bool get _esSaldar => !widget.saldo.saldado && _de == widget.saldo.deudor;

  /// Lo tecleado, o `null` si todavía no es un importe válido.
  double? get _importe {
    final valor = double.tryParse(_importeController.text.replaceAll(',', '.'));
    return (valor == null || valor <= 0) ? null : valor;
  }

  /// Cómo quedarían las cuentas si se guardara esto.
  String get _resultado {
    final importe = _importe;
    if (importe == null) return 'Pon cuánto se pasa para ver cómo queda.';

    // Quien pone el dinero sube en el saldo: la deuda baja si lo pone quien
    // debe, y sube si lo pone el otro (que entonces adelanta todavía más).
    final restante = _de == widget.saldo.deudor
        ? widget.saldo.importe - importe
        : widget.saldo.importe + importe;

    if (restante.abs() < 0.005) return 'Después de esto quedáis en paz.';
    // Pasar de más no es un error: le da la vuelta a la deuda.
    if (restante < 0) {
      return 'Después de esto, ${widget.saldo.acreedor} le deberá '
          '${euros(-restante)} a ${widget.saldo.deudor}.';
    }
    return 'Después de esto, ${widget.saldo.deudor} le seguirá debiendo '
        '${euros(restante)} a ${widget.saldo.acreedor}.';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _save() async {
    final importe = _importe;
    if (importe == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pon un importe mayor que 0.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.saveSettlement(
        de: _de,
        para: _para,
        importe: importe,
        fecha: _fecha,
        concepto: _esSaldar ? conceptoSaldar : conceptoPrestamo,
        nota: _notaController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se ha podido guardar: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final importe = _importe;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pasar dinero', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _BalanceCard(saldo: widget.saldo),
            const SizedBox(height: 20),
            Text('¿Quién pone el dinero?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: personaA, label: Text(personaA)),
                ButtonSegment(value: personaB, label: Text(personaB)),
              ],
              selected: {_de},
              onSelectionChanged: (v) => setState(() => _de = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _importeController,
              decoration: InputDecoration(
                labelText: 'Importe (€)',
                helperText: _esSaldar ? '$_de le devuelve el dinero a $_para' : '$_de le pasa el dinero a $_para',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Fecha', suffixIcon: Icon(Icons.calendar_today)),
                child: Text('${_fecha.day}/${_fecha.month}/${_fecha.year}'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notaController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Bizum, efectivo, para qué era...',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_resultado, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      importe == null
                          ? (_esSaldar ? 'Saldar' : 'Pasar dinero')
                          : '${_esSaldar ? 'Saldar' : 'Pasar'} ${euros(importe)}',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El cuadro de arriba: cómo están las cuentas antes de tocar nada.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.saldo});

  final SettlementBalance saldo;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final detalle = [
      if (saldo.gastosContados > 0)
        'De ${saldo.gastosContados} ${saldo.gastosContados == 1 ? 'gasto compartido' : 'gastos compartidos'}',
      if (saldo.ultimaLiquidacion case final fecha?)
        'Última liquidación el ${fecha.day}/${fecha.month}/${fecha.year}',
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            saldo.saldado ? 'Estáis en paz' : '${saldo.deudor} le debe a ${saldo.acreedor}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            euros(saldo.importe),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (detalle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(detalle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
