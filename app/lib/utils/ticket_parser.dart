/// Analiza el texto crudo que devuelve el OCR de un ticket y lo convierte en
/// líneas de producto limpias: descarta lo que evidentemente no es un
/// artículo (direcciones, NIF, totales, pies de ticket...) y extrae el
/// precio, distinguiendo entre precio por unidad, precio por peso (kg) y
/// líneas "N x precio" (p.ej. "2 x 0,90" por dos latas), que se convierten en
/// N líneas individuales para que cada unidad quede como un gasto separado.
library;

/// Una línea de ticket ya limpia, lista para categorizar.
class ParsedTicketLine {
  ParsedTicketLine({required this.descripcion, this.precioTotal, this.pesoGramos});

  final String descripcion;
  final double? precioTotal;
  final double? pesoGramos;
}

double _toDouble(String s) => double.parse(s.replaceAll(',', '.').replaceAll(' ', ''));

double _round2(double v) => double.parse(v.toStringAsFixed(2));

// ---------------------------------------------------------------------------
// Reglas de descarte: líneas que evidentemente no son un producto.
// ---------------------------------------------------------------------------

final List<RegExp> _noiseLinePatterns = [
  // Direcciones.
  RegExp(r'\bC\/\s*[A-ZÁÉÍÓÚÑ]'),
  RegExp(r'\b(CALLE|AVDA|AVENIDA|PLAZA|PZA|POLIGONO|POL\.?\s*IND|CTRA|CARRETERA|PASEO|URB|URBANIZACION)\b'),
  // código postal + población: "28029 MADRID", "28029 - MADRID (MADRID)" o
  // "28020, MADRID" (a veces el OCR pone una coma en vez de un espacio solo).
  RegExp(r'\b\d{5}\b\s*[-–,]?\s*\(?[A-ZÁÉÍÓÚÑ]{3,}'),
  // Identificación fiscal y contacto.
  RegExp(r'\b(C\.?I\.?F\.?|N\.?I\.?F\.?)\s*[:.]?\s*[A-Z0-9]'),
  RegExp(r'\b[A-Z]\d{7}[0-9A-Z]\b'), // CIF suelto sin etiqueta (letra + 8 dígitos/control), p.ej. "A28600278"
  RegExp(r'\b(TEL|TELF|TLF|TELEFONO|FAX)\.?\s*[:.]?\s*\d'),
  RegExp(r'(WWW\.|HTTP|\.COM\b|\.ES\b|\.NET\b|@)'),
  RegExp(r'^\d{8}[A-Z]$'), // NIF suelto
  RegExp(r'^\d{9}$'), // teléfono suelto
  RegExp(r'^[A-Z]?\d{3,}\s*\/\s*\d{3,}$'), // código de referencia suelto, p.ej. "S103108/0045209"
  // Cabecera / pie de ticket.
  RegExp(r'\bTICKET\b|\bALBARAN\b'),
  RegExp(r'\b(OPERADOR[A]?|CAJER[OA]|TERMINAL|LE\s+ATENDI[OÓ]|ATENDI[OÓ] POR|N.\s*CAJA|CAJA\s*[:.]?\s*\d+|TIQUE\s*[:.]?\s*\d+)\b'),
  RegExp(r'\b(HORA|FECHA)\s*[:.]'),
  RegExp(r'^\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}([\s,]+\d{1,2}[:.]\d{2})?'), // fecha, opcionalmente con hora y texto detrás
  RegExp(r'\bUNID\.?\s+C.DIGO\b|\bC.DIGO\b.*\bDESCRIPCION\b'), // cabecera de tabla "UNID CODIGO DESCRIPCION TOTAL"
  RegExp(r'\bDESGLOSE\b'),
  // Totales, pagos e impuestos. "TOTAL" no entra aquí a propósito: si
  // apareciera en mitad de un nombre real ("COLGATE TOTAL...") lo borraría
  // por error. La línea de total de verdad la corta _isHardStopLine, que solo
  // dispara cuando "TOTAL" abre la línea.
  RegExp(
    r'\b(SUBTOTAL|BASE IMPONIBLE|I\.?V\.?A\.?|TARJETA|EFECTIVO|CAMBIO|DEVUELTO|ENTREGAD[OA]|DEVOLUCION|AUTORIZACION|N.\s*OPERACION|PUNTOS|AHORRO)\b',
  ),
  // Fila de desglose de IVA: "B  21,00%  1,49  0,31  1,80". OJO: no
  // generalizamos a "cualquier % es ruido" porque hay productos reales con
  // un porcentaje en el nombre (p.ej. "QUESO BLANCO 0% M. GRASA").
  RegExp(r'^[A-E]\s+\d{1,2}[.,]\d{2}\s*%'),
  // Razón social del comercio (típicamente la primera línea del ticket). El
  // separador entre letras puede ser un punto o, si el OCR se equivoca, una
  // coma ("S,L.U." en vez de "S.L.U.").
  RegExp(r'\b(S[.,]?L[.,]?U?[.,]?|S[.,]?A[.,]?U?[.,]?|S[.,]?COOP[.,]?|C[.,]?B[.,]?)(\s|,|$)'),
];

/// Palabras clave de cabecera/pie que se comprueban quitando antes cualquier
/// carácter que no sea una letra (espacios, dígitos, puntuación) y quitando
/// acentos: así da igual que el OCR meta un espacio a media palabra
/// ("Fac tura"), cambie una letra por un dígito parecido ("simp1ificada") o
/// se coma un acento ("NUMERO" vs "NÚMERO").
const _compactNoiseKeywords = [
  'FACTURA',
  'ATENCIONALCLIENTE',
  'GRACIASPORSU',
  'NUMERODEARTICULOS',
  'FORMADEPAGO',
  'FORMASDEPAGO',
  'DESCRIPCION', // cabecera de tabla "...DESCRIPCION TOTAL" partida en dos líneas por el OCR
];

String _compact(String upperLine) {
  return upperLine
      .replaceAll(RegExp('[ÁÀÄÂ]'), 'A')
      .replaceAll(RegExp('[ÉÈËÊ]'), 'E')
      .replaceAll(RegExp('[ÍÌÏÎ]'), 'I')
      .replaceAll(RegExp('[ÓÒÖÔ]'), 'O')
      .replaceAll(RegExp('[ÚÙÜÛ]'), 'U')
      .replaceAll('Ñ', 'N')
      .replaceAll(RegExp(r'[^A-Z]'), '');
}

bool _hasCompactKeyword(String upperLine) {
  final compact = _compact(upperLine);
  return _compactNoiseKeywords.any(compact.contains);
}

/// Marcadores que indican que ya hemos llegado al total del ticket: a partir
/// de aquí (forma de pago, desglose de IVA, número de artículos, código de
/// factura...) ya no hay más productos, así que dejamos de procesar líneas.
/// Evitamos "AHORRO" porque algunos tickets muestran un resumen de ahorro
/// antes de terminar de listar los artículos.
bool _isHardStopLine(String upperLine) {
  if (upperLine.contains('AHORRO')) return false;
  // OJO: aquí solo "forma de pago" (y "total"), nunca los demás
  // _compactNoiseKeywords como FACTURA — esa puede aparecer en la CABECERA
  // del ticket (antes de cualquier producto, p.ej. Flying Tiger la imprime
  // ahí), y cortar el ticket entero por eso sería un desastre. Esas otras
  // palabras solo se usan para descartar esa línea suelta, nunca para dejar
  // de leer el resto del ticket.
  final compact = _compact(upperLine);
  if (compact.contains('FORMADEPAGO') || compact.contains('FORMASDEPAGO')) return true;
  // "TOTAL" solo cuenta si abre la línea Y lleva un importe: así no cortamos
  // ni por productos reales que lo lleven en el nombre ("COLGATE TOTAL...")
  // ni por la cabecera de una tabla ("...DESCRIPCION TOTAL") que a veces el
  // OCR separa como su propia línea suelta sin ningún precio.
  if (RegExp(r'^TOTAL\b').hasMatch(upperLine)) {
    return RegExp(r'\d{1,4}[.,]\d{2}').hasMatch(upperLine);
  }
  return false;
}

/// `true` si alguna palabra de la línea tiene mayúsculas y minúsculas
/// mezcladas de forma errática (p.ej. "AHORRaMaS"): así es como suele salir
/// el logo estilizado del comercio al pasar por el OCR, nunca un producto
/// real (los tickets imprimen los artículos en una tipografía uniforme).
bool _hasScrambledCase(String line) {
  for (final word in line.split(RegExp(r'\s+'))) {
    final letters = word.split('').where((c) => RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(c)).toList();
    if (letters.length < 5) continue;
    var transitions = 0;
    for (var i = 1; i < letters.length; i++) {
      final prevUpper = letters[i - 1] == letters[i - 1].toUpperCase();
      final curUpper = letters[i] == letters[i].toUpperCase();
      if (prevUpper != curUpper) transitions++;
    }
    if (transitions >= 3) return true;
  }
  return false;
}

/// `true` si la línea es evidentemente ruido (no un producto): direcciones,
/// NIF/CIF, teléfonos, totales, pies de ticket, logos del comercio, separadores
/// sin texto...
bool isNoiseLine(String line) {
  final trimmed = line.trim();
  if (trimmed.length < 3) return true;
  if (_hasScrambledCase(trimmed)) return true;
  final upper = trimmed.toUpperCase();
  if (_hasCompactKeyword(upper)) return true;
  for (final pattern in _noiseLinePatterns) {
    if (pattern.hasMatch(upper)) return true;
  }
  if (!RegExp(r'[A-ZÁÉÍÓÚÑ]').hasMatch(upper)) return true; // sin letras: código de barras, separador...
  return false;
}

/// Palabras que son unidad de medida o relleno, no parte de un nombre de
/// producto: "2 UN x 0,90", "3 UDS x 1,20"... "UN"/"UD" son abreviaturas de
/// "unidad(es)" y no deben confundirse con un producto real.
const _unitWordsPattern = r'KGS?|GRS?|UDS?|UNIDADES?|UNID\.?|UNI\.?|UN|X|EUR';

/// `true` si, quitando números y palabras de unidad/relleno, no queda nada:
/// o bien es una línea de continuación ("2 UN x 0,90" o
/// "0,608 kg x 1,49 €/kg 0,91") que hay que fusionar con la línea de
/// descripción anterior, o bien es la "descripción" residual que ha
/// capturado por error una de las expresiones de cantidad/precio.
bool _isFillerOnly(String text) {
  final residual = text
      .toUpperCase()
      .replaceAll(RegExp(r'[0-9.,]'), '')
      .replaceAll(RegExp('\\b($_unitWordsPattern)\\b'), '')
      .replaceAll(RegExp(r'\b[A-E]\b'), '') // columna suelta de tipo de IVA ("B", "C"...)
      .replaceAll(RegExp(r'[€/\s]'), '');
  return residual.isEmpty;
}

/// `true` si la línea contiene un patrón de cantidad×precio o peso×precio/kg
/// que no viene precedido de nada más que relleno (p.ej. "2 UN x 0,90" o
/// "0,608 kg x 1,49 €/kg 0,91"): candidata a ser la continuación, en la línea
/// siguiente, del precio de la línea de descripción anterior.
///
/// Solo exigimos que no haya nada raro ANTES del patrón, no después: el OCR a
/// veces pega texto suelto (marcas de agua de seguridad del papel, letras de
/// columnas vecinas...) detrás del precio, y no por eso deja de ser la
/// continuación de la línea anterior. Si el patrón apareciera después de
/// texto real (p.ej. "COCA COLA 2X0,75L 1,50", un tamaño de pack dentro del
/// propio nombre del producto), esa parte previa ya no sería relleno y no lo
/// tratamos como continuación.
bool _looksLikeContinuation(String line) {
  final qtyMatch = _qtyPattern.firstMatch(line);
  if (qtyMatch != null && _isFillerOnly(line.substring(0, qtyMatch.start))) return true;
  final weightMatch = _weightPattern.firstMatch(line);
  if (weightMatch != null && _isFillerOnly(line.substring(0, weightMatch.start))) return true;
  return false;
}

// ---------------------------------------------------------------------------
// Extracción de precio: unidad simple, precio por kilo, o "N x precio".
// ---------------------------------------------------------------------------

// Importe monetario con dos decimales. Se admite un espacio suelto justo
// detrás de la coma/punto ("1, 19") porque el OCR a veces lo mete por error;
// _toDouble ya se encarga de quitarlo antes de convertir a número.
const _moneyPattern = r'\d{1,4}[.,]\s?\d{2}';

/// "0,608 kg ... 1,49 €/kg" — venta a peso (fruta, verdura, carnicería...). El
/// símbolo € antes de "/kg" a veces lo lee el OCR como una "E" suelta
/// (p.ej. "9,99E/Kg") o como un dígito de más (p.ej. "1,896/Kg" en vez de
/// "1,89€/Kg"), así que aceptamos ambos. Sin "\b" tras el primer "Kg": el OCR
/// a veces pega la "x" siguiente sin espacio ("1,195 Kgx 1,49€/Kg"), y un
/// límite de palabra ahí impediría reconocerlo.
final _weightPattern = RegExp('(\\d+[.,]\\d{1,3})\\s*KGS?\\.?.*?($_moneyPattern)\\s*(?:€|E|\\d)?\\s*/\\s*KGS?\\.?', caseSensitive: false);

/// "2 CERVEZA LATA 0,45 0,90" — cantidad al principio, precio unidad y total al final.
final _leadingQtyPattern = RegExp('^(\\d{1,3})\\s+(.+?)\\s+($_moneyPattern)\\s+($_moneyPattern)\\s*€?\$');

/// "1  3073611  CALABAZA LUMINOSA G  8,00" — formato tabular con columna de
/// código de artículo (p.ej. tickets de Flying Tiger): cantidad (opcional; el
/// OCR a veces se come el "1" inicial), código (entero, sin coma decimal),
/// descripción y total.
final _qtyCodeDescPattern = RegExp('^(?:(\\d{1,3})\\s+)?(\\d{4,8})\\s+(.+?)\\s+($_moneyPattern)\\s*€?\$');

/// "CERVEZA LATA 2 x 0,45", "2 UN x 0,45" o "2x0,45" — cantidad (con o sin la
/// palabra "unidad(es)" de por medio) y precio unidad en cualquier punto.
final _qtyPattern = RegExp('(\\d{1,3})\\s*(?:(?:UDS?|UNIDADES?|UNID\\.?|UNI\\.?|UN)\\s*)?[xX]\\s*($_moneyPattern)', caseSensitive: false);

/// Precio al final de la línea (caso más habitual: "DESCRIPCION ... 1,99").
final _trailingPricePattern = RegExp('($_moneyPattern)\\s*€?\\s*\$');

class _LineParse {
  _LineParse({required this.descripcion, this.precioTotal, this.cantidad = 1, this.pesoGramos});

  final String descripcion;
  final double? precioTotal;
  final int cantidad;
  final double? pesoGramos;
}

/// Analiza una línea suelta. [asContinuation] se pone a `true` cuando la
/// línea se está evaluando como posible continuación (peso/cantidad) de la
/// línea de descripción anterior:
/// en ese caso no importa que no tenga delante un nombre de producto, porque
/// solo vamos a usar su precio/cantidad/peso, nunca su descripción. Si se
/// evalúa como línea primaria (`asContinuation: false`) y el patrón de
/// peso/cantidad no tiene ningún texto real delante, es que se trata de un
/// resto huérfano (la fusión hacia delante no encontró destino, normalmente
/// porque el precio real ya está en otra línea vecina) y no lo convertimos en
/// un producto inventado con el propio peso/cantidad como si fuera su nombre.
_LineParse _parseSingleLine(String line, {bool asContinuation = false}) {
  final weightMatch = _weightPattern.firstMatch(line);
  if (weightMatch != null) {
    final descripcion = line.substring(0, weightMatch.start).trim();
    if (descripcion.isEmpty && !asContinuation) {
      return _LineParse(descripcion: line.trim());
    }
    final pesoKg = _toDouble(weightMatch.group(1)!);
    final precioKg = _toDouble(weightMatch.group(2)!);
    final trailing = _trailingPricePattern.firstMatch(line.substring(weightMatch.end));
    final descripcionFinal = descripcion.isEmpty ? line.trim() : descripcion;
    if (trailing != null) {
      // Si el ticket ya trae el total impreso, es la fuente más fiable (el
      // peso o el precio/kg pueden venir con algún dígito mal leído por el
      // OCR, p.ej. "9,360 Kg" en vez de "0,360 Kg"). Si no cuadra ni de
      // lejos con lo que da peso × precio/kg, nos quedamos con el total
      // impreso pero no mostramos un peso que sabemos que está mal.
      final printedTotal = _toDouble(trailing.group(1)!);
      final computedTotal = _round2(pesoKg * precioKg);
      if ((printedTotal - computedTotal).abs() > 0.05) {
        return _LineParse(descripcion: descripcionFinal, precioTotal: printedTotal);
      }
      return _LineParse(descripcion: descripcionFinal, precioTotal: printedTotal, pesoGramos: pesoKg * 1000);
    }
    return _LineParse(descripcion: descripcionFinal, precioTotal: _round2(pesoKg * precioKg), pesoGramos: pesoKg * 1000);
  }

  final leadingMatch = _leadingQtyPattern.firstMatch(line);
  if (leadingMatch != null) {
    final cantidad = int.parse(leadingMatch.group(1)!);
    final unit = _toDouble(leadingMatch.group(3)!);
    final total = _toDouble(leadingMatch.group(4)!);
    final descripcion = leadingMatch.group(2)!.trim();
    // Si lo que ha capturado como "descripción" es en realidad solo la
    // palabra "UN"/"UD" (p.ej. "2 UN X 0,90  1,80"), no es un producto: es
    // una línea de cantidad suelta que debe fusionarse con la línea anterior.
    if (cantidad > 0 && cantidad < 100 && (cantidad * unit - total).abs() < 0.02 && !_isFillerOnly(descripcion)) {
      return _LineParse(descripcion: descripcion, precioTotal: total, cantidad: cantidad);
    }
  }

  final qtyCodeMatch = _qtyCodeDescPattern.firstMatch(line);
  if (qtyCodeMatch != null) {
    final cantidad = qtyCodeMatch.group(1) != null ? int.parse(qtyCodeMatch.group(1)!) : 1;
    final descripcion = qtyCodeMatch.group(3)!.trim();
    final total = _toDouble(qtyCodeMatch.group(4)!);
    if (cantidad > 0 && cantidad < 100 && !_isFillerOnly(descripcion)) {
      return _LineParse(descripcion: descripcion, precioTotal: total, cantidad: cantidad);
    }
  }

  final qtyMatch = _qtyPattern.firstMatch(line);
  if (qtyMatch != null) {
    final descripcion = line.substring(0, qtyMatch.start).trim();
    if (descripcion.isEmpty && !asContinuation) {
      return _LineParse(descripcion: line.trim());
    }
    final cantidad = int.parse(qtyMatch.group(1)!);
    final unit = _toDouble(qtyMatch.group(2)!);
    final rest = line.substring(qtyMatch.end);
    final trailing = _trailingPricePattern.firstMatch(rest);
    final total = trailing != null ? _toDouble(trailing.group(1)!) : _round2(cantidad * unit);
    return _LineParse(descripcion: descripcion.isEmpty ? line.trim() : descripcion, precioTotal: total, cantidad: cantidad);
  }

  final trailing = _trailingPricePattern.firstMatch(line);
  if (trailing != null) {
    return _LineParse(descripcion: line.substring(0, trailing.start).trim(), precioTotal: _toDouble(trailing.group(1)!));
  }

  // Sin ningún precio detectable: si al menos la línea es "CODIGO DESCRIPCION"
  // (p.ej. "3055619   SELLOS. 9 UDS"), quitamos el código suelto para que la
  // descripción quede limpia; el precio lo tendrá que rellenar el usuario.
  final bareCodeMatch = RegExp(r'^\d{4,8}\s+(.+)$').firstMatch(line);
  if (bareCodeMatch != null) {
    final descripcion = bareCodeMatch.group(1)!.trim();
    if (!_isFillerOnly(descripcion)) {
      return _LineParse(descripcion: descripcion);
    }
  }

  return _LineParse(descripcion: line.trim());
}

/// Columna suelta de tipo de IVA (p.ej. "COLINES INTEGRALES ALIPENDE   C")
/// que, al reconstruir la fila a partir de columnas OCR separadas, queda
/// pegada al final de la descripción. Solo se quita cuando la letra está
/// separada por dos o más espacios (indicio de que era su propia columna),
/// para no comerse una letra suelta que sea parte real del nombre.
final _trailingVatLetterPattern = RegExp(r'\s{2,}[A-E]$');

String _stripTrailingVatLetter(String descripcion) {
  return descripcion.replaceFirst(_trailingVatLetterPattern, '').trimRight();
}

/// Reparte [total] entre [cantidad] unidades en céntimos exactos, de modo que
/// la suma de las partes siga siendo exactamente [total] (sin descuadres de
/// redondeo cuando el total no es múltiplo exacto del número de unidades).
List<double> _splitEvenly(double total, int cantidad) {
  final totalCents = (total * 100).round();
  final baseCents = totalCents ~/ cantidad;
  var remainder = totalCents - baseCents * cantidad;
  return List.generate(cantidad, (i) {
    final cents = baseCents + (remainder-- > 0 ? 1 : 0);
    return cents / 100;
  });
}

/// Convierte el texto crudo del OCR en líneas de producto limpias: descarta
/// ruido, une líneas de precio/peso que vienen sueltas en la línea siguiente,
/// y explota las líneas "N x precio" en N líneas individuales (una por
/// unidad) para que cada una se pueda categorizar y sumar por separado.
List<ParsedTicketLine> parseReceiptLines(String rawText) {
  final rawLines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final result = <ParsedTicketLine>[];

  var i = 0;
  while (i < rawLines.length) {
    final line = rawLines[i];
    i++;
    final upper = line.toUpperCase();
    // A partir del total ya no hay más productos: lo que sigue es forma de
    // pago, desglose de IVA, número de artículos, código de factura...
    if (_isHardStopLine(upper)) break;
    if (isNoiseLine(line)) continue;
    // Resto huérfano de peso/cantidad (p.ej. "1,940 Kg x 13,99€/Kg") que no
    // se fusionó con la línea anterior porque esta ya tenía su propio
    // precio: no tiene ningún nombre de producto delante, así que la
    // descartamos en vez de mostrarla como un artículo sin sentido.
    if (_looksLikeContinuation(line)) continue;

    var parsed = _parseSingleLine(line);
    if (parsed.precioTotal == null && i < rawLines.length && _looksLikeContinuation(rawLines[i])) {
      final continuation = _parseSingleLine(rawLines[i], asContinuation: true);
      if (continuation.precioTotal != null) {
        parsed = _LineParse(
          descripcion: parsed.descripcion,
          precioTotal: continuation.precioTotal,
          cantidad: continuation.cantidad,
          pesoGramos: continuation.pesoGramos,
        );
        i++; // consumimos también la línea de continuación
      }
    } else if (parsed.precioTotal != null && parsed.cantidad == 1 && i < rawLines.length && _looksLikeContinuation(rawLines[i])) {
      // El desglose de cantidad o peso a veces llega SUELTO justo después de
      // una línea que ya trae su propio precio total (p.ej.
      // "BOLSA...   0,30€" seguido de "2 Un x 0,15€/Un"). Si el total que
      // calcula esa línea coincide con el que ya teníamos, no es un producto
      // nuevo: es la cantidad/peso de este mismo artículo, y la usamos para
      // repartir el precio en unidades individuales.
      final continuation = _parseSingleLine(rawLines[i], asContinuation: true);
      if (continuation.precioTotal != null && (continuation.precioTotal! - parsed.precioTotal!).abs() < 0.02) {
        parsed = _LineParse(
          descripcion: parsed.descripcion,
          precioTotal: parsed.precioTotal,
          cantidad: continuation.cantidad,
          pesoGramos: continuation.pesoGramos ?? parsed.pesoGramos,
        );
        i++;
      }
    }

    if (parsed.precioTotal != null && parsed.descripcion.length <= 3 && result.isNotEmpty && result.last.precioTotal == null) {
      // El nombre del producto se partió en dos líneas por el ancho de la
      // columna (p.ej. "LECHE ALIPENDE 1L SEMIDESNA" + "Se   6 Un x
      // 0,84€/Un   5,04€"): la línea anterior se quedó sin precio, y este
      // trocito suelto de texto es solo el final de su nombre pegado a la
      // cantidad/precio real, no un producto en sí.
      final previous = result.removeLast();
      parsed = _LineParse(
        descripcion: previous.descripcion,
        precioTotal: parsed.precioTotal,
        cantidad: parsed.cantidad,
        pesoGramos: parsed.pesoGramos,
      );
    }

    final descripcion = _stripTrailingVatLetter(parsed.descripcion);
    if (parsed.cantidad > 1 && parsed.precioTotal != null) {
      for (final precio in _splitEvenly(parsed.precioTotal!, parsed.cantidad)) {
        result.add(ParsedTicketLine(descripcion: descripcion, precioTotal: precio));
      }
    } else {
      result.add(ParsedTicketLine(descripcion: descripcion, precioTotal: parsed.precioTotal, pesoGramos: parsed.pesoGramos));
    }
  }
  return result;
}
