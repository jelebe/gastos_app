/// Todo lo que la pantalla de inicio enseña de un mes.
///
/// Va junto en un único objeto porque se calcula de una sola pasada: los seis
/// bloques miran los mismos documentos, así que pedirlos por separado
/// significaba releer los tickets del mes una vez por bloque.
class DashboardSummary {
  DashboardSummary({
    required this.gastosPorMes,
    required this.ingresosPorMes,
    required this.categoryBreakdown,
    required this.categoryComparison,
    required this.personBreakdown,
    required this.personTotalSpending,
  });

  /// Totales de los últimos meses, en orden cronológico y acabando en el mes
  /// que se está mirando. La clave de cada entrada es "AAAA-MM".
  final List<MapEntry<String, double>> gastosPorMes;
  final List<MapEntry<String, double>> ingresosPorMes;

  /// Gasto del mes por grupo de categoría, de mayor a menor.
  final List<MapEntry<String, double>> categoryBreakdown;

  /// El mismo gasto por grupo junto al del mes anterior, para la variación.
  final List<({String grupo, double actual, double anterior})> categoryComparison;

  /// Reparto del gasto compartido por quién lo pagó, de mayor a menor.
  final List<MapEntry<String, double>> personBreakdown;

  /// Lo que ha gastado cada uno en total, contando también lo personal y
  /// repartiendo al 50% lo pagado por "Ambos".
  final List<MapEntry<String, double>> personTotalSpending;

  /// Los totales del mes que se está mirando: es el último de la serie, que
  /// acaba justo en él.
  double get gastoDelMes => gastosPorMes.isEmpty ? 0 : gastosPorMes.last.value;
  double get ingresoDelMes => ingresosPorMes.isEmpty ? 0 : ingresosPorMes.last.value;
  double get balance => ingresoDelMes - gastoDelMes;
}
