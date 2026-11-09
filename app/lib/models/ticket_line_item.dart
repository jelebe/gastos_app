class TicketLineItem {
  TicketLineItem({
    required this.textoOriginal,
    this.precioTotal,
    this.categoriaId,
    this.grupo,
    this.productoNormalizado,
    this.trackWeight = false,
    this.pesoGramos,
    this.alPeso = false,
    this.textoEscaneado,
    this.categoriaIdSugerida,
  });

  String textoOriginal;
  double? precioTotal;
  String? categoriaId;
  String? grupo;
  String? productoNormalizado;
  bool trackWeight;
  double? pesoGramos;

  /// Si el ticket la traía vendida al peso ("kg x €/kg"). Se aprende junto al
  /// texto, así que no cambia aunque luego se escriba el peso a mano.
  final bool alPeso;

  /// Texto tal cual lo leyó el escáner, aunque luego se corrija a mano: es el
  /// que volverá a salir en el próximo ticket, así que es el que se aprende.
  final String? textoEscaneado;

  /// Categoría propuesta por parecido (no por haber guardado ya esta misma
  /// línea), para marcarla como pendiente de revisar.
  String? categoriaIdSugerida;

  bool get isCategorized => categoriaId != null && productoNormalizado != null;

  /// Tiene la categoría propuesta por parecido y nadie la ha cambiado.
  bool get sugerida => categoriaIdSugerida != null && categoriaId == categoriaIdSugerida;

  /// Texto con el que se aprende esta línea al guardar.
  String get textoParaAprender => textoEscaneado ?? textoOriginal;
}
