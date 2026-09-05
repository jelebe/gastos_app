import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/ticket_line_item.dart';
import '../models/transaction_summary.dart';
import '../services/household_repository.dart';

/// Paleta categórica de referencia (orden fijo, nunca se reordena ni se
/// genera un color nuevo para una serie de más: a partir de la 8ª se pliega
/// en "Otros").
const _categoricalPalette = [
  Color(0xFF2A78D6), // 1 azul
  Color(0xFFEB6834), // 2 naranja
  Color(0xFF1BAF7A), // 3 aguamarina
  Color(0xFFEDA100), // 4 amarillo
  Color(0xFFE87BA4), // 5 magenta
  Color(0xFF008300), // 6 verde
  Color(0xFF4A3AA7), // 7 violeta
  Color(0xFFE34948), // 8 rojo
];

const _successGreen = Color(0xFF006300);
const _statusCritical = Color(0xFFD03B3B);
const _mutedInk = Color(0xFF898781);
const _secondaryInk = Color(0xFF52514E);
const _gridline = Color(0xFFE1E0D9);

const _mesesCorto = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic', //
];

class _DashboardData {
  _DashboardData({
    required this.gastosPorMes,
    required this.ingresosPorMes,
    required this.categoryBreakdown,
    required this.categoryComparison,
    required this.personBreakdown,
    required this.personTotalSpending,
  });

  final List<MapEntry<String, double>> gastosPorMes;
  final List<MapEntry<String, double>> ingresosPorMes;
  final List<MapEntry<String, double>> categoryBreakdown;
  final List<({String grupo, double actual, double anterior})> categoryComparison;
  final List<MapEntry<String, double>> personBreakdown;
  final List<MapEntry<String, double>> personTotalSpending;

  double get gastoMesActual => gastosPorMes.isEmpty ? 0 : gastosPorMes.last.value;
  double get ingresoMesActual => ingresosPorMes.isEmpty ? 0 : ingresosPorMes.last.value;
  double get balance => ingresoMesActual - gastoMesActual;
}

/// Resumen visual: KPIs del mes, gasto por categoría, evolución de los
/// últimos meses y los movimientos más recientes.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key, required this.repository});

  final HouseholdRepository repository;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final now = DateTime.now();
    final mesActual = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    // Se lanzan todas antes de esperar ninguna para que corran en paralelo
    // (loadCategoryComparison devuelve un tipo distinto a las demás, así que
    // no cabe en un único Future.wait sin perder el tipado).
    final gastosPorMesFuture = widget.repository.loadMonthlyTotals(tipo: 'gasto');
    final ingresosPorMesFuture = widget.repository.loadMonthlyTotals(tipo: 'ingreso');
    final categoryBreakdownFuture = widget.repository.loadCategoryBreakdown(mesActual);
    final categoryComparisonFuture = widget.repository.loadCategoryComparison(mesActual);
    final personBreakdownFuture = widget.repository.loadPersonBreakdown(mesActual);
    final personTotalSpendingFuture = widget.repository.loadPersonTotalSpending(mesActual);

    return _DashboardData(
      gastosPorMes: await gastosPorMesFuture,
      ingresosPorMes: await ingresosPorMesFuture,
      categoryBreakdown: await categoryBreakdownFuture,
      categoryComparison: await categoryComparisonFuture,
      personBreakdown: await personBreakdownFuture,
      personTotalSpending: await personTotalSpendingFuture,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _KpiRow(gasto: data.gastoMesActual, ingreso: data.ingresoMesActual, balance: data.balance),
              const SizedBox(height: 28),
              Text('Gasto por categoría este mes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _CategoryBreakdown(entries: data.categoryBreakdown),
              const SizedBox(height: 28),
              Text('Reparto del gasto compartido', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Solo cuenta el gasto compartido, no el personal.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(entries: data.personBreakdown),
              const SizedBox(height: 28),
              Text('Total gastado por cada uno este mes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Todo lo que gasta cada uno, compartido y personal ("Ambos" se reparte al 50%).',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(entries: data.personTotalSpending),
              const SizedBox(height: 28),
              Text('Comparado con el mes anterior', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _CategoryComparison(entries: data.categoryComparison),
              const SizedBox(height: 28),
              Text('Últimos 6 meses', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _MonthlyTrendChart(gastos: data.gastosPorMes, ingresos: data.ingresosPorMes),
              const SizedBox(height: 28),
              Text('Últimos movimientos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _RecentMovements(repository: widget.repository),
            ],
          );
        },
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.gasto, required this.ingreso, required this.balance});

  final double gasto;
  final double ingreso;
  final double balance;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatTile(label: 'Ingresos este mes', value: ingreso, color: _successGreen)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Gastos este mes', value: gasto, color: _categoricalPalette[7])),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Balance',
            value: balance,
            color: balance >= 0 ? _successGreen : _categoricalPalette[7],
            signed: true,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color, this.signed = false});

  final String label;
  final double value;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final texto = '${signed && value > 0 ? '+' : ''}${value.toStringAsFixed(2)} €';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: _mutedInk, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              texto,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reparto del gasto del mes: una única barra apilada (parte-todo) más su
/// leyenda con importe y porcentaje directamente etiquetados.
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.entries});

  final List<MapEntry<String, double>> entries;

  static const _maxSlots = 7;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('Todavía no hay gasto registrado este mes.', style: TextStyle(color: _mutedInk));
    }

    final visibles = entries.take(_maxSlots).toList();
    if (entries.length > _maxSlots) {
      final restoTotal = entries.skip(_maxSlots).fold<double>(0, (sum, e) => sum + e.value);
      visibles.add(MapEntry('Otros', restoTotal));
    }
    final total = visibles.fold<double>(0, (sum, e) => sum + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                for (var i = 0; i < visibles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2), // hueco de superficie entre segmentos
                  Expanded(
                    flex: (visibles[i].value * 1000).round().clamp(1, 1 << 30),
                    child: Container(color: _colorFor(i)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < visibles.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: _colorFor(i), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(visibles[i].key, overflow: TextOverflow.ellipsis)),
                Text(
                  '${visibles[i].value.toStringAsFixed(2)} € · ${(visibles[i].value / total * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: _secondaryInk, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _colorFor(int i) => i < _categoricalPalette.length ? _categoricalPalette[i] : _mutedInk;
}

/// Variación del gasto por categoría respecto al mes anterior, en %. Gastar
/// más se marca en rojo (empeora), gastar menos en verde (mejora); una
/// categoría sin gasto el mes anterior se marca como "Nuevo" en vez de un
/// porcentaje sin sentido (dividir por cero).
class _CategoryComparison extends StatelessWidget {
  const _CategoryComparison({required this.entries});

  final List<({String grupo, double actual, double anterior})> entries;

  @override
  Widget build(BuildContext context) {
    final visibles = entries.where((e) => e.actual > 0 || e.anterior > 0).toList();
    if (visibles.isEmpty) {
      return const Text('Todavía no hay suficiente gasto para comparar.', style: TextStyle(color: _mutedInk));
    }
    return Column(
      children: [
        for (final e in visibles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(child: Text(e.grupo, overflow: TextOverflow.ellipsis)),
                Text('${e.actual.toStringAsFixed(2)} €', style: const TextStyle(color: _secondaryInk)),
                const SizedBox(width: 12),
                SizedBox(width: 56, child: _DeltaBadge(actual: e.actual, anterior: e.anterior)),
              ],
            ),
          ),
      ],
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.actual, required this.anterior});

  final double actual;
  final double anterior;

  @override
  Widget build(BuildContext context) {
    if (anterior <= 0) {
      return const Text('Nuevo', textAlign: TextAlign.end, style: TextStyle(color: _mutedInk, fontSize: 12, fontWeight: FontWeight.w600));
    }
    final delta = (actual - anterior) / anterior * 100;
    // Un margen de 0.5% evita marcar como "cambio" el ruido de céntimos.
    final sube = delta > 0.5;
    final baja = delta < -0.5;
    final color = sube ? _statusCritical : (baja ? _successGreen : _mutedInk);
    final icono = sube ? Icons.arrow_upward : (baja ? Icons.arrow_downward : Icons.remove);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: color),
        const SizedBox(width: 2),
        Text('${delta.abs().toStringAsFixed(0)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

class _MonthlyTrendChart extends StatelessWidget {
  const _MonthlyTrendChart({required this.gastos, required this.ingresos});

  final List<MapEntry<String, double>> gastos;
  final List<MapEntry<String, double>> ingresos;

  @override
  Widget build(BuildContext context) {
    final maxY = [...gastos, ...ingresos].map((e) => e.value).fold<double>(0, (m, v) => v > m ? v : m);
    final techo = maxY <= 0 ? 10.0 : maxY * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: techo,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: techo / 4,
                getDrawingHorizontalLine: (_) => const FlLine(color: _gridline, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= gastos.length) return const SizedBox.shrink();
                      final mes = int.parse(gastos[i].key.split('-')[1]);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_mesesCorto[mes - 1], style: const TextStyle(color: _mutedInk, fontSize: 11)),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    '${rod.toY.toStringAsFixed(2)} €',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < gastos.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: i < ingresos.length ? ingresos[i].value : 0,
                        color: _categoricalPalette[0],
                        width: 8,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      BarChartRodData(
                        toY: gastos[i].value,
                        color: _categoricalPalette[1],
                        width: 8,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: _categoricalPalette[0], label: 'Ingresos'),
            const SizedBox(width: 16),
            _LegendDot(color: _categoricalPalette[1], label: 'Gastos'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _secondaryInk, fontSize: 12)),
      ],
    );
  }
}

class _RecentMovements extends StatefulWidget {
  const _RecentMovements({required this.repository});

  final HouseholdRepository repository;

  @override
  State<_RecentMovements> createState() => _RecentMovementsState();
}

class _RecentMovementsState extends State<_RecentMovements> {
  // El stream se crea una sola vez: si se creara dentro de build(), cada
  // rebuild de esta pantalla (p.ej. al hacer pull-to-refresh) haría que
  // StreamBuilder se resuscribiera de golpe a un stream "nuevo".
  late final Stream<List<TransactionSummary>> _stream = widget.repository.watchRecentTransactions();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionSummary>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final movimientos = snapshot.data!;
        if (movimientos.isEmpty) {
          return const Text('Todavía no hay movimientos registrados.', style: TextStyle(color: _mutedInk));
        }
        return Column(
          children: [
            for (final m in movimientos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () => _showMovementDetail(context, widget.repository, m),
                title: Text(
                  m.tipo == 'ingreso' ? (m.categoriaNombre ?? 'Ingreso') : ((m.comercio?.trim().isNotEmpty ?? false) ? m.comercio!.trim() : 'Ticket'),
                ),
                subtitle: Text('${m.fecha.day}/${m.fecha.month}/${m.fecha.year}'),
                trailing: Text(
                  '${m.tipo == 'ingreso' ? '+' : '-'}${m.importeTotal.toStringAsFixed(2)} €',
                  style: TextStyle(
                    color: m.tipo == 'ingreso' ? _successGreen : null,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ventana con el desglose de un movimiento: las líneas del ticket si es un
/// gasto, o la categoría y la nota si es un ingreso.
Future<void> _showMovementDetail(BuildContext context, HouseholdRepository repository, TransactionSummary tx) async {
  final esIngreso = tx.tipo == 'ingreso';
  List<TicketLineItem>? items;
  if (!esIngreso) {
    final categories = await repository.loadCategories();
    items = await repository.loadTicketItems(tx.id, categories);
  }
  if (!context.mounted) return;

  final titulo = esIngreso
      ? (tx.categoriaNombre ?? 'Ingreso')
      : ((tx.comercio?.trim().isNotEmpty ?? false) ? tx.comercio!.trim() : 'Ticket');

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [
                '${tx.fecha.day}/${tx.fecha.month}/${tx.fecha.year}',
                if (tx.pagadoPor != null) 'Pagado por ${tx.pagadoPor}',
                if (!tx.compartido) 'Personal (no cuenta en el reparto)',
              ].join(' · '),
              style: const TextStyle(color: _mutedInk),
            ),
            if (tx.nota != null) ...[
              const SizedBox(height: 8),
              Text(tx.nota!),
            ],
            const SizedBox(height: 16),
            const Divider(),
            if (!esIngreso)
              if (items == null || items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No se han encontrado líneas para este ticket.', style: TextStyle(color: _mutedInk)),
                )
              else
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.textoOriginal),
                    subtitle: Text(item.productoNormalizado ?? 'Sin categoría'),
                    trailing: Text(
                      [
                        if (item.precioTotal != null) '${item.precioTotal!.toStringAsFixed(2)} €',
                        if (item.pesoGramos != null) '${item.pesoGramos!.toStringAsFixed(0)} g',
                      ].join('\n'),
                      textAlign: TextAlign.end,
                    ),
                  ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '${esIngreso ? '+' : ''}${tx.importeTotal.toStringAsFixed(2)} €',
                  style: TextStyle(fontWeight: FontWeight.bold, color: esIngreso ? _successGreen : null),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
