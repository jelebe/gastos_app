/// Una compra concreta de un producto: una línea de ticket con los datos del
/// ticket del que salió.
///
/// [mesContable] es el mes al que se apunta esa compra, que ya viene
/// calculado: aquí no se sabe dónde empieza cada mes.
typedef ProductPurchase = ({
  double precio,
  double? pesoGramos,
  double? precioPorKilo,
  DateTime fecha,
  String? comercio,
  String? pagadoPor,
  bool compartido,
  String mesContable,
});

/// Lo más barato que se ha encontrado un producto, y dónde.
typedef CheapestBuy = ({double precioPorKilo, String? comercio, DateTime fecha});

/// Lo que cuesta un producto en una tienda concreta.
typedef StorePrice = ({String comercio, double precioPorKilo, int compras, double gastado});

/// La ficha de un producto: cuánto se gasta en él, a qué precio y cuándo.
class ProductSummary {
  ProductSummary({
    required this.producto,
    required this.grupo,
    required this.total,
    required this.compras,
    required this.porMes,
    required this.lineas,
    this.pesoTotalGramos,
    this.precioMedioPorKilo,
    this.masBarato,
    this.porComercio = const [],
    this.ahorroPosible,
  });

  final String producto;
  final String? grupo;

  /// Lo gastado en la ventana de meses que se está mirando, y en cuántas
  /// compras.
  final double total;
  final int compras;

  /// Lo gastado en cada mes de la ventana, en orden cronológico y acabando en
  /// el mes que se mira. Los meses sin ninguna compra van a cero, para que la
  /// evolución no se lea como si el hueco no existiera.
  final List<MapEntry<String, double>> porMes;

  /// Las compras, de la más reciente a la más antigua.
  final List<ProductPurchase> lineas;

  /// Solo de las compras que iban al peso: si el producto no se vende así,
  /// estos tres son nulos.
  final double? pesoTotalGramos;
  final double? precioMedioPorKilo;
  final CheapestBuy? masBarato;

  /// Lo que cuesta el producto en cada tienda, de la más barata a la más cara.
  ///
  /// Solo entra lo vendido al peso: sin gramos no hay precio por kilo que
  /// comparar, y comparar precios totales de bolsas distintas no dice nada.
  /// Tampoco entra lo comprado sin tienda apuntada.
  final List<StorePrice> porComercio;

  /// Lo que te habrías ahorrado comprando siempre en la tienda más barata, a
  /// igualdad de cantidad. Nulo si no hay con qué comparar.
  final double? ahorroPosible;

  /// Hay al menos dos tiendas con precio, que es cuando comparar tiene
  /// sentido.
  bool get sePuedeCompararTiendas => porComercio.length > 1;

  /// Lo gastado en el mes que se está mirando, que es el último de la ventana.
  double get totalDelMes => porMes.isEmpty ? 0 : porMes.last.value;

  /// Las compras del mes que se está mirando, de la más reciente a la más
  /// antigua. Las del resto de la ventana solo sirven para el histórico.
  List<ProductPurchase> get lineasDelMes =>
      porMes.isEmpty ? const [] : [for (final l in lineas) if (l.mesContable == porMes.last.key) l];

  /// Si hay algo que contar del precio por kilo.
  bool get tienePrecioPorKilo => precioMedioPorKilo != null;
}

/// El resumen que dejan estas compras.
///
/// Se separa de la consulta para poder probarlo sin Firestore. [meses] son las
/// claves de la ventana en orden cronológico: marcan qué meses salen en la
/// evolución, aunque en alguno no se haya comprado nada.
ProductSummary resumenDeProducto({
  required String producto,
  required String? grupo,
  required List<String> meses,
  required Iterable<ProductPurchase> compras,
}) {
  final porMes = {for (final mes in meses) mes: 0.0};
  final lineas = <ProductPurchase>[];

  var total = 0.0;
  // Del precio por kilo solo se puede hablar de lo que iba al peso: una media
  // que mezclara lo vendido por unidad saldría sin sentido.
  var pesoTotal = 0.0;
  var gastadoAlPeso = 0.0;
  CheapestBuy? masBarato;
  final porTienda = <String, ({double gastado, double gramos, int compras})>{};

  for (final compra in compras) {
    lineas.add(compra);
    total += compra.precio;
    if (porMes.containsKey(compra.mesContable)) {
      porMes[compra.mesContable] = porMes[compra.mesContable]! + compra.precio;
    }

    final peso = compra.pesoGramos;
    if (peso == null || peso <= 0) continue;
    pesoTotal += peso;
    gastadoAlPeso += compra.precio;

    // El precio por kilo viene guardado en la línea, pero si falta se saca del
    // precio y el peso, que es como se calculó en su día.
    final porKilo = compra.precioPorKilo ?? compra.precio / (peso / 1000);
    if (masBarato == null || porKilo < masBarato.precioPorKilo) {
      masBarato = (precioPorKilo: porKilo, comercio: compra.comercio, fecha: compra.fecha);
    }

    final tienda = compra.comercio?.trim();
    if (tienda == null || tienda.isEmpty) continue;
    final acumulado = porTienda[tienda];
    porTienda[tienda] = (
      gastado: (acumulado?.gastado ?? 0) + compra.precio,
      gramos: (acumulado?.gramos ?? 0) + peso,
      compras: (acumulado?.compras ?? 0) + 1,
    );
  }

  // Cada tienda con su media ponderada, igual que la global: dos kilos caros y
  // cien gramos baratos no salen a mitad de camino.
  final precios = [
    for (final MapEntry(key: tienda, value: datos) in porTienda.entries)
      (
        comercio: tienda,
        precioPorKilo: datos.gastado / (datos.gramos / 1000),
        compras: datos.compras,
        gastado: datos.gastado,
      ),
  ]..sort((a, b) => a.precioPorKilo.compareTo(b.precioPorKilo));

  lineas.sort((a, b) => b.fecha.compareTo(a.fecha));

  return ProductSummary(
    producto: producto,
    grupo: grupo,
    total: total,
    compras: lineas.length,
    porMes: [for (final mes in meses) MapEntry(mes, porMes[mes]!)],
    lineas: lineas,
    pesoTotalGramos: pesoTotal > 0 ? pesoTotal : null,
    // Media ponderada por peso, no media de los precios por kilo: comprar dos
    // kilos caros y cien gramos baratos no sale a mitad de camino.
    precioMedioPorKilo: pesoTotal > 0 ? gastadoAlPeso / (pesoTotal / 1000) : null,
    masBarato: masBarato,
    porComercio: precios,
    // Lo mismo comprado siempre al precio de la más barata. Solo tiene sentido
    // si hay más de una con la que comparar.
    ahorroPosible: precios.length > 1
        ? gastadoAlPeso - (pesoTotal / 1000) * precios.first.precioPorKilo
        : null,
  );
}
