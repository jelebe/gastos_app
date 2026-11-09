/// Lo gastado en un producto al peso dentro de un mes, que es lo que permite
/// saber a qué precio salía el kilo entonces.
///
/// Solo entra lo vendido al peso: sin gramos no hay precio por kilo, y comparar
/// precios totales de envases distintos no dice nada del precio.
typedef ProductPricePoint = ({String producto, String mes, double gastado, double gramos});

/// Cuánto ha cambiado el precio de un producto entre los dos tramos.
typedef ProductPriceChange = ({
  String producto,
  double precioAntes,
  double precioAhora,

  /// La variación en tanto por uno: 0,12 es un 12 % más caro.
  double variacion,

  /// Lo gastado en él en el tramo reciente, que es lo que le da peso en el
  /// índice: lo que más compras es lo que más te afecta.
  double gastoAhora,
});

/// Cuánto ha subido lo que compras, comparando dos tramos de meses.
///
/// No es la inflación oficial ni pretende serlo: es el precio de **tu** cesta,
/// medido con tus propios tickets. Por eso pesa cada producto por lo que gastas
/// en él ahora, no por una cesta teórica.
class BasketInflation {
  BasketInflation({
    required this.variacion,
    required this.cambios,
    required this.mesesAntes,
    required this.mesesAhora,
    required this.productosDescartados,
  });

  /// La subida media en tanto por uno, o nulo si no hay ningún producto que se
  /// pueda comparar todavía. Nulo no es cero: es "aún no se sabe".
  final double? variacion;

  /// Producto a producto, de la subida más grande a la bajada más grande.
  final List<ProductPriceChange> cambios;

  /// Qué meses se han comparado, para poder decirlo en pantalla.
  final List<String> mesesAntes;
  final List<String> mesesAhora;

  /// Cuántos productos se han quedado fuera por no tener precio en los dos
  /// tramos. Se dice en pantalla: explica por qué el número sale de tan poco.
  final int productosDescartados;

  bool get hayDatos => variacion != null;

  /// Los que más han subido, que es lo que de verdad se mira.
  Iterable<ProductPriceChange> get subidas => cambios.where((c) => c.variacion > 0);

  /// Los que han bajado, de la bajada más grande a la más pequeña.
  Iterable<ProductPriceChange> get bajadas => cambios.reversed.where((c) => c.variacion < 0);
}

/// El índice de precios que dejan estos puntos.
///
/// Se compara el precio medio por kilo de cada producto en [mesesAhora] contra
/// el que tenía en [mesesAntes]. Se comparan tramos de varios meses y no dos
/// meses sueltos porque un producto no se compra todos los meses: con un mes a
/// cada lado, la mitad de la cesta se quedaría fuera.
///
/// Un producto solo entra si tiene precio en los dos tramos. Los que no, se
/// cuentan aparte: son la medida de cuánta cesta se está quedando fuera.
BasketInflation inflacionDeCesta({
  required Iterable<ProductPricePoint> puntos,
  required List<String> mesesAntes,
  required List<String> mesesAhora,
}) {
  final antes = <String, ({double gastado, double gramos})>{};
  final ahora = <String, ({double gastado, double gramos})>{};

  for (final punto in puntos) {
    if (punto.gramos <= 0) continue;
    final destino = mesesAhora.contains(punto.mes)
        ? ahora
        : mesesAntes.contains(punto.mes)
            ? antes
            : null;
    if (destino == null) continue;
    final acumulado = destino[punto.producto];
    destino[punto.producto] = (
      gastado: (acumulado?.gastado ?? 0) + punto.gastado,
      gramos: (acumulado?.gramos ?? 0) + punto.gramos,
    );
  }

  final cambios = <ProductPriceChange>[];
  var pesoTotal = 0.0;
  var sumaPonderada = 0.0;

  for (final MapEntry(key: producto, value: reciente) in ahora.entries) {
    final viejo = antes[producto];
    if (viejo == null) continue;

    final precioAntes = viejo.gastado / (viejo.gramos / 1000);
    final precioAhora = reciente.gastado / (reciente.gramos / 1000);
    if (precioAntes <= 0) continue;

    cambios.add((
      producto: producto,
      precioAntes: precioAntes,
      precioAhora: precioAhora,
      variacion: precioAhora / precioAntes - 1,
      gastoAhora: reciente.gastado,
    ));
    // Media ponderada por lo que se gasta ahora en cada cosa: que el aceite
    // suba un 30 % pesa más que el perejil, porque el aceite se lleva más
    // dinero.
    pesoTotal += reciente.gastado;
    sumaPonderada += reciente.gastado * (precioAhora / precioAntes);
  }

  cambios.sort((a, b) => b.variacion.compareTo(a.variacion));

  return BasketInflation(
    variacion: pesoTotal > 0 ? sumaPonderada / pesoTotal - 1 : null,
    cambios: cambios,
    mesesAntes: mesesAntes,
    mesesAhora: mesesAhora,
    // Lo que se compra ahora pero no se compraba antes (o al revés): no se
    // puede comparar, pero sí decir cuánto se queda fuera.
    productosDescartados: {...ahora.keys, ...antes.keys}.length - cambios.length,
  );
}
