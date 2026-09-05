class TicketLineItem {
  TicketLineItem({required this.textoOriginal, this.precioTotal, this.categoriaId, this.grupo, this.productoNormalizado, this.trackWeight = false, this.pesoGramos});

  String textoOriginal;
  double? precioTotal;
  String? categoriaId;
  String? grupo;
  String? productoNormalizado;
  bool trackWeight;
  double? pesoGramos;

  bool get isCategorized => categoriaId != null && productoNormalizado != null;
}
