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
