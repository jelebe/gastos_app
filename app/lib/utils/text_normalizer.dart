const _accentMap = {
  'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A',
  'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
  'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
  'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O',
  'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
  'Ñ': 'N',
};

/// Normaliza una línea de texto de ticket para poder compararla contra el
/// diccionario de alias: mayúsculas, sin acentos, espacios colapsados.
String normalizeLine(String text) {
  final upper = text.toUpperCase();
  final buffer = StringBuffer();
  for (final rune in upper.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentMap[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

final _trailingPricePattern = RegExp(r'(\d{1,4}[.,]\d{2})\s*€?\s*$');

/// Intenta separar una línea de ticket en descripción + precio, asumiendo el
/// formato más común en tickets españoles: "DESCRIPCION ... PRECIO" al final
/// de la línea. Si no encuentra un precio con formato decimal, devuelve solo
/// la descripción y deja el precio para que lo rellene el usuario.
({String descripcion, double? precio}) splitDescriptionAndPrice(String line) {
  final match = _trailingPricePattern.firstMatch(line);
  if (match == null) {
    return (descripcion: line.trim(), precio: null);
  }
  final priceText = match.group(1)!.replaceAll(',', '.');
  final precio = double.tryParse(priceText);
  final descripcion = line.substring(0, match.start).trim();
  if (descripcion.isEmpty || precio == null) {
    return (descripcion: line.trim(), precio: null);
  }
  return (descripcion: descripcion, precio: precio);
}
