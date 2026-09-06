import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/dashboard_summary.dart';
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

const _mesesLargo = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', //
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre', //
];

/// "Septiembre 2026" a partir del primer día de ese mes.
String _etiquetaMes(DateTime mes) => '${_mesesLargo[mes.month - 1]} ${mes.year}';

/// Resumen visual: KPIs del mes, gasto por categoría, evolución de los
/// últimos meses y los movimientos más recientes. Se puede mirar cualquier
/// mes pasado, no solo el que corre.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key, required this.repository, required this.refreshTick});

  final HouseholdRepository repository;

  /// Cambia cada vez que se guarda o se borra algo fuera de esta pantalla.
  /// Se recargan los datos, pero sin rehacer el widget: así el mes que se
  /// está mirando no se pierde al volver de guardar un gasto.
  final int refreshTick;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  /// Primer día del mes que se está mirando.
  late DateTime _mes = _mesEnCurso;
  late Future<DashboardSummary> _future = _load();

  static DateTime get _mesEnCurso {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  /// No se puede avanzar más allá del mes en curso: del futuro no hay nada
  /// que enseñar.
  bool get _esMesEnCurso => !_mes.isBefore(_mesEnCurso);

  Future<DashboardSummary> _load() => widget.repository.loadDashboardSummary(mesDe(_mes));

  @override
  void didUpdateWidget(covariant DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      setState(() {
        _future = _load();
      });
    }
  }

  void _volverAlMesEnCurso() {
    setState(() {
      _mes = _mesEnCurso;
      _future = _load();
    });
  }

  void _cambiarMes(int deltaMeses) {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + deltaMeses);
      _future = _load();
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    // Con cuerpo de bloque, no con `=>`: una flecha devuelve el valor de la
    // asignación (el propio Future), y setState rechaza un callback que
    // devuelva un Future, así que el refresco no llegaba a repintar.
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final mes = mesDe(_mes);
    final etiqueta = _etiquetaMes(_mes);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<DashboardSummary>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _MonthSelector(
                etiqueta: etiqueta,
                onAnterior: () => _cambiarMes(-1),
                onSiguiente: _esMesEnCurso ? null : () => _cambiarMes(1),
                onHoy: _esMesEnCurso ? null : _volverAlMesEnCurso,
              ),
              const SizedBox(height: 16),
              _KpiRow(gasto: data.gastoDelMes, ingreso: data.ingresoDelMes, balance: data.balance),
              const SizedBox(height: 28),
              Text('Gasto por categoría', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Toca una categoría para ver qué se ha comprado en ella.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(
                entries: data.categoryBreakdown,
                onTapEntry: (grupo) => _showGroupDetail(context, widget.repository, mes, etiqueta, grupo),
              ),
              const SizedBox(height: 28),
              Text('Reparto del gasto compartido', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Solo cuenta el gasto compartido, no el personal.',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(
                entries: data.personBreakdown,
                onTapEntry: (persona) => _showPersonDetail(
                  context,
                  widget.repository,
                  mes,
                  etiqueta,
                  persona,
                  soloCompartido: true,
                ),
              ),
              const SizedBox(height: 28),
              Text('Total gastado por cada uno', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Todo lo que gasta cada uno, compartido y personal ("Ambos" se reparte al 50%).',
                style: TextStyle(color: _mutedInk, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _CategoryBreakdown(
                entries: data.personTotalSpending,
                onTapEntry: (persona) => _showPersonDetail(
                  context,
                  widget.repository,
                  mes,
                  etiqueta,
                  persona,
                  soloCompartido: false,
                ),
              ),
              const SizedBox(height: 28),
              Text('Comparado con el mes anterior', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _CategoryComparison(entries: data.categoryComparison),
              const SizedBox(height: 28),
              Text('Evolución (6 meses)', style: Theme.of(context).textTheme.titleMedium),
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

/// Cabecera para moverse de mes en mes. La flecha de avanzar se apaga en el
/// mes en curso, y el propio nombre del mes devuelve a él de un toque.
class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.etiqueta,
    required this.onAnterior,
    this.onSiguiente,
    this.onHoy,
  });

  final String etiqueta;
  final VoidCallback onAnterior;

  /// Nulos cuando ya se está en el mes en curso: ni se puede avanzar al
  /// futuro, ni tiene sentido ofrecer "volver a hoy".
  final VoidCallback? onSiguiente;
  final VoidCallback? onHoy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: onAnterior,
        ),
        InkWell(
          onTap: onHoy,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  etiqueta,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (onHoy != null)
                  const Text('Volver a este mes', style: TextStyle(color: _mutedInk, fontSize: 11)),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: onSiguiente,
        ),
      ],
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
///
/// Si se pasa [onTapEntry], cada fila de la leyenda se puede tocar para ver
/// el detalle de lo que hay detrás. El tramo "Otros" no: no es una categoría
/// real, sino la suma de todas las que no caben en la barra.
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.entries, this.onTapEntry});

  final List<MapEntry<String, double>> entries;
  final ValueChanged<String>? onTapEntry;

  static const _maxSlots = 7;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('Todavía no hay gasto registrado este mes.', style: TextStyle(color: _mutedInk));
    }

    // "esAgregado" marca el tramo que agrupa a las categorías que no caben en
    // la barra: no se puede abrir su detalle. Va como bandera y no por su
    // nombre porque existe un grupo de categorías llamado "Otros" de verdad.
    final visibles = [
      for (final e in entries.take(_maxSlots)) (key: e.key, value: e.value, esAgregado: false),
    ];
    if (entries.length > _maxSlots) {
      final restoTotal = entries.skip(_maxSlots).fold<double>(0, (sum, e) => sum + e.value);
      visibles.add((key: 'Otros', value: restoTotal, esAgregado: true));
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
          _LegendRow(
            color: _colorFor(i),
            label: visibles[i].key,
            value: visibles[i].value,
            porcentaje: total <= 0 ? 0 : visibles[i].value / total * 100,
            onTap: (onTapEntry == null || visibles[i].esAgregado)
                ? null
                : () => onTapEntry!(visibles[i].key),
          ),
      ],
    );
  }

  Color _colorFor(int i) => i < _categoricalPalette.length ? _categoricalPalette[i] : _mutedInk;
}

/// Una fila de la leyenda: color, nombre, importe y porcentaje. Si se puede
/// abrir su detalle se marca con una flecha, para que se vea que hay algo
/// debajo y no parezca una etiqueta muerta.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.porcentaje,
    this.onTap,
  });

  final Color color;
  final String label;
  final double value;
  final double porcentaje;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fila = Padding(
      padding: EdgeInsets.symmetric(vertical: onTap == null ? 4 : 6),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          Text(
            '${value.toStringAsFixed(2)} € · ${porcentaje.toStringAsFixed(0)}%',
            style: const TextStyle(color: _secondaryInk, fontWeight: FontWeight.w600),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: _mutedInk),
        ],
      ),
    );
    if (onTap == null) return fila;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: fila);
  }
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

/// Cabecera común de las hojas de detalle: título, una línea de contexto y el
/// total de lo que se está listando.
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.titulo, required this.contexto, required this.total});

  final String titulo;
  final String contexto;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(contexto, style: const TextStyle(color: _mutedInk)),
        const SizedBox(height: 12),
        Text(
          '${total.toStringAsFixed(2)} €',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
  }
}

/// Detalle de un grupo de categoría del mes: todas las líneas de ticket que
/// han caído en él, para poder ver de dónde sale el importe del gráfico.
Future<void> _showGroupDetail(
  BuildContext context,
  HouseholdRepository repository,
  String mes,
  String mesEtiqueta,
  String grupo,
) async {
  final lineas = await repository.loadGroupLines(mes, grupo);
  if (!context.mounted) return;

  final total = lineas.fold<double>(0, (sum, l) => sum + l.precio);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            _DetailHeader(
              titulo: grupo,
              contexto: '${lineas.length} ${lineas.length == 1 ? 'línea' : 'líneas'} en $mesEtiqueta',
              total: total,
            ),
            if (lineas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No hay gasto de este grupo en este mes.', style: TextStyle(color: _mutedInk)),
              )
            else
              for (final linea in lineas)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(linea.textoOriginal.trim().isEmpty ? (linea.producto ?? 'Sin nombre') : linea.textoOriginal),
                  subtitle: Text(
                    [
                      if (linea.producto != null) linea.producto!,
                      '${linea.fecha.day}/${linea.fecha.month}/${linea.fecha.year}',
                      if (linea.comercio?.trim().isNotEmpty ?? false) linea.comercio!.trim(),
                      if (linea.pagadoPor != null) linea.pagadoPor!,
                      if (!linea.compartido) 'Personal',
                    ].join(' · '),
                  ),
                  trailing: Text(
                    [
                      '${linea.precio.toStringAsFixed(2)} €',
                      if (linea.pesoGramos != null) '${linea.pesoGramos!.toStringAsFixed(0)} g',
                    ].join('\n'),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

/// Detalle del gasto de una persona en el mes. Con [soloCompartido] se listan
/// solo los tickets compartidos que pagó ella (lo que se reparte); sin él, se
/// lista todo lo que le toca, incluidos los tickets pagados por "Ambos", que
/// cuentan a la mitad.
Future<void> _showPersonDetail(
  BuildContext context,
  HouseholdRepository repository,
  String mes,
  String mesEtiqueta,
  String persona, {
  required bool soloCompartido,
}) async {
  final gastos = await repository.loadMonthExpenses(mes);
  if (!context.mounted) return;

  bool esDeLaPersona(TransactionSummary tx) =>
      tx.pagadoPor == persona || (persona == 'Sin especificar' && tx.pagadoPor == null);

  final visibles = gastos.where((tx) {
    if (soloCompartido) return tx.compartido && esDeLaPersona(tx);
    return esDeLaPersona(tx) || tx.pagadoPor == 'Ambos';
  }).toList();

  // Un ticket de "Ambos" solo aporta la mitad al total de cada uno, igual que
  // en el gráfico del que se ha abierto este detalle.
  double importeImputado(TransactionSummary tx) =>
      (!soloCompartido && tx.pagadoPor == 'Ambos' && persona != 'Ambos')
          ? tx.importeTotal / 2
          : tx.importeTotal;

  final total = visibles.fold<double>(0, (sum, tx) => sum + importeImputado(tx));

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: scrollController,
          children: [
            _DetailHeader(
              titulo: persona,
              contexto: soloCompartido
                  ? '${visibles.length} ${visibles.length == 1 ? 'gasto compartido' : 'gastos compartidos'} en $mesEtiqueta'
                  : '${visibles.length} ${visibles.length == 1 ? 'gasto' : 'gastos'} en $mesEtiqueta (compartidos y personales)',
              total: total,
            ),
            if (visibles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No hay gastos de esta persona en este mes.', style: TextStyle(color: _mutedInk)),
              )
            else
              for (final tx in visibles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text((tx.comercio?.trim().isNotEmpty ?? false) ? tx.comercio!.trim() : 'Ticket'),
                  subtitle: Text(
                    [
                      '${tx.fecha.day}/${tx.fecha.month}/${tx.fecha.year}',
                      if (importeImputado(tx) != tx.importeTotal) 'Ambos · 50% de ${tx.importeTotal.toStringAsFixed(2)} €',
                      if (!tx.compartido) 'Personal',
                      if (tx.nota != null) tx.nota!,
                    ].join(' · '),
                  ),
                  trailing: Text(
                    '${importeImputado(tx).toStringAsFixed(2)} €',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}
