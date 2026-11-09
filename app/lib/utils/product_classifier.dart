import 'dart:math';

import '../models/category.dart';
import 'text_normalizer.dart';

/// Texto de una línea de ticket reducido a lo que sirve para reconocerla:
/// mayúsculas, sin acentos ni signos, y con las confusiones típicas del
/// lector de la foto entre letras y números corregidas dentro de cada palabra
/// ("TRITURAD0" → "TRITURADO", "1K" → "IK"). El resto de números (gramos,
/// unidades, precios) se quitan: no dicen qué producto es y cambian de un
/// ticket a otro.
///
/// Dos textos con la misma clave se consideran la misma línea.
String lineKey(String text) {
  final palabras = normalizeLine(text).replaceAll(RegExp(r'[^A-Z0-9]+'), ' ').split(' ');
  final clave = <String>[];
  for (final palabra in palabras) {
    if (!palabra.contains(RegExp('[A-Z]'))) continue;
    // Un 0 o un 1 sueltos junto a letras suelen ser una O o una I mal leídas;
    // un número de varias cifras ("360G") es una cantidad y se quita.
    final corregida = palabra.replaceAllMapped(RegExp('[0-9]+'), (m) => switch (m[0]) {
          '0' => 'O',
          '1' => 'I',
          _ => '',
        });
    if (corregida.isNotEmpty) clave.add(corregida);
  }
  return clave.join(' ');
}

/// Lo que se decidió para una línea al guardar un ticket: su categoría, o que
/// no era un producto. Es lo que el clasificador aprende.
class LearnedLine {
  const LearnedLine({required this.clave, required this.alPeso, required this.decision, this.veces = 1});

  /// Valor de [decision] para las líneas que no son productos (total, forma
  /// de pago...). Firestore reserva los ids con doble guion bajo, así que
  /// ninguna categoría puede llamarse igual.
  static const noProducto = '__no_producto__';

  /// Ver [lineKey].
  final String clave;

  /// Si se vendió al peso (el ticket traía "kg x €/kg"). La misma clave al
  /// peso y por unidad son líneas distintas: queso al corte frente a cuña.
  final bool alPeso;

  /// Id de la categoría o [noProducto]. Si una línea se ha guardado con
  /// categorías distintas, cuenta la última: así se corrigen los errores.
  final String decision;
  final int veces;

  bool get esNoProducto => decision == noProducto;

  /// Id del documento en Firestore: la misma clave, igual de al peso,
  /// comparte documento.
  static String docId(String clave, bool alPeso) {
    final id = '${alPeso ? 'peso' : 'unidad'}_${clave.replaceAll(' ', '_')}';
    return id.length <= 400 ? id : id.substring(0, 400);
  }
}

enum Certeza {
  /// Esta misma línea ya se guardó antes: no hace falta revisarla.
  aprendida,

  /// Se parece a algo aprendido o al nombre de una categoría: conviene echarle
  /// un vistazo.
  probable,
}

class LineGuess {
  const LineGuess._({this.categoria, required this.certeza, required this.puntuacion});

  /// Categoría propuesta, o `null` si la línea no es un producto.
  final Category? categoria;
  final Certeza certeza;

  /// De 0 a 1, cuánto se parece a aquello en lo que se basa.
  final double puntuacion;

  bool get noProducto => categoria == null;
}

/// Propone categoría para las líneas de un ticket, o dice cuáles no son
/// productos, a partir de lo aprendido de los tickets guardados y de los
/// nombres de las categorías. Todo en memoria y en milisegundos.
///
/// En orden:
/// 1. La misma línea ya guardada (misma [lineKey] e igual de al peso).
/// 2. Una línea guardada muy parecida, comparando trozos de tres letras: así
///    "OUESO MOZZAPELLA" se reconoce como "QUESO MOZZARELLA".
/// 3. El nombre de una categoría: "QUESO ... CUNA" encaja con "Queso cuña"
///    aunque nunca se haya guardado, y "PECHUGA POLLO" prefiere "Pechuga
///    Pollo corte" a "Pollo" porque coinciden más palabras.
///
/// Que la línea vaya al peso o no desempata entre categorías parecidas ("Queso"
/// al peso frente a "Queso cuña"), pero no descarta ninguna: muchas categorías
/// al peso se compran también envasadas.
class ProductClassifier {
  ProductClassifier({required List<Category> categorias, required Iterable<LearnedLine> aprendidas}) {
    _categoriaPorId = {for (final c in categorias) c.id: c};
    for (final linea in aprendidas) {
      if (linea.clave.isEmpty) continue;
      if (!linea.esNoProducto && !_categoriaPorId.containsKey(linea.decision)) continue; // categoría borrada
      _exactas['${linea.alPeso}|${linea.clave}'] = linea;
      _ejemplos.add(_Ejemplo(linea, _trigramas(linea.clave)));
    }
    final df = <String, int>{};
    for (final ejemplo in _ejemplos) {
      for (final g in ejemplo.trigramas.keys) {
        df[g] = (df[g] ?? 0) + 1;
      }
    }
    _idfTrigrama = {for (final e in df.entries) e.key: log((_ejemplos.length + 1) / (e.value + 1)) + 1};
    for (final ejemplo in _ejemplos) {
      ejemplo.vector = _vector(ejemplo.trigramas);
    }

    for (final c in categorias) {
      if (c.tipo != 'gasto') continue;
      final palabras = _palabras(c.nombre).toSet().toList();
      if (palabras.isNotEmpty) _nombres.add((categoria: c, palabras: palabras));
    }
    final dfPalabra = <String, int>{};
    for (final n in _nombres) {
      for (final p in n.palabras) {
        dfPalabra[p] = (dfPalabra[p] ?? 0) + 1;
      }
    }
    _idfPalabra = {for (final e in dfPalabra.entries) e.key: log((_nombres.length + 1) / (e.value + 1)) + 1};
  }

  /// A partir de este parecido con una línea aprendida se propone su categoría.
  static const umbralParecida = 0.72;

  /// Parecidísima (típicamente el mismo texto con alguna letra mal leída): se
  /// aplica como aprendida, sin pedir revisión.
  static const umbralCasiIgual = 0.9;

  /// Para quitar una línea por parecerse a otra que no era producto se exige
  /// algo más que para proponer categoría, porque quitar por error es peor.
  /// Una sola letra mal leída en una línea corta ya deja el parecido en torno
  /// a 0,8, así que más arriba solo se quitarían las idénticas.
  static const umbralNoProducto = 0.75;

  /// Penalización cuando la línea y la categoría (o la línea aprendida) no
  /// coinciden en ir al peso.
  static const _factorPeso = 0.85;

  late final Map<String, Category> _categoriaPorId;
  final _exactas = <String, LearnedLine>{};
  final _ejemplos = <_Ejemplo>[];
  late final Map<String, double> _idfTrigrama;
  final _nombres = <({Category categoria, List<String> palabras})>[];
  late final Map<String, double> _idfPalabra;

  LineGuess? classify(String texto, {required bool alPeso}) {
    final clave = lineKey(texto);
    if (clave.isEmpty) return null;

    final exacta = _exactas['$alPeso|$clave'];
    if (exacta != null) return _guess(exacta.decision, Certeza.aprendida, 1);

    final porNombre = _mejorPorNombre(clave, alPeso);
    final parecida = _mejorParecida(clave, alPeso);
    if (parecida != null) {
      final (:decision, :puntuacion) = parecida;
      if (decision == LearnedLine.noProducto) {
        if (puntuacion >= umbralNoProducto) return _guess(decision, Certeza.probable, puntuacion);
      } else if (puntuacion >= umbralCasiIgual) {
        return _guess(decision, Certeza.aprendida, puntuacion);
      } else if (puntuacion >= umbralParecida) {
        // Parecerse en letras no basta si cambia justo la palabra que importa:
        // "PECHUGA POLLO ASADA" se parece mucho a "PECHUGA PAVO ASADA". Si el
        // nombre de una categoría encaja claramente y dice otra cosa, manda.
        final nombreClaro = porNombre != null &&
            porNombre.categoria.trackWeight == alPeso &&
            porNombre.cobertura >= 0.66 &&
            porNombre.categoria.id != decision;
        if (!nombreClaro) return _guess(decision, Certeza.probable, puntuacion);
      }
    }

    if (porNombre != null) {
      return LineGuess._(categoria: porNombre.categoria, certeza: Certeza.probable, puntuacion: porNombre.cobertura);
    }
    return null;
  }

  LineGuess _guess(String decision, Certeza certeza, double puntuacion) => LineGuess._(
        categoria: decision == LearnedLine.noProducto ? null : _categoriaPorId[decision],
        certeza: certeza,
        puntuacion: puntuacion,
      );

  ({String decision, double puntuacion})? _mejorParecida(String clave, bool alPeso) {
    if (_ejemplos.isEmpty) return null;
    final vector = _vector(_trigramas(clave));
    _Ejemplo? mejor;
    var mejorPuntuacion = 0.0;
    for (final ejemplo in _ejemplos) {
      var puntuacion = _coseno(vector, ejemplo.vector);
      if (ejemplo.linea.alPeso != alPeso) puntuacion *= _factorPeso;
      if (puntuacion > mejorPuntuacion) {
        mejor = ejemplo;
        mejorPuntuacion = puntuacion;
      }
    }
    return mejor == null ? null : (decision: mejor.linea.decision, puntuacion: mejorPuntuacion);
  }

  /// La categoría cuyo nombre mejor encaja con las palabras de la línea. Cada
  /// palabra del nombre suma según lo rara que sea entre los nombres de
  /// categoría ("PECHUGA" dice más que "POLLO") y resta, a medias, si no
  /// aparece: así "Pollo bandeja" no gana a "Pollo" con una línea sin
  /// "BANDEJA", pero "Pechuga Pollo corte" sí gana a "Pollo" con "PECHUGA
  /// POLLO".
  ///
  /// Se prefieren las categorías que coinciden en ir al peso: "JUDIAS VERDES
  /// 360G" sin peso es "Judías verdes tarro", no "Judías verdes" al peso. Solo
  /// si ninguna de esas encaja se mira el resto.
  ({Category categoria, double cobertura})? _mejorPorNombre(String clave, bool alPeso) {
    final palabrasLinea = _palabras(clave);
    // El lector a veces parte una palabra en dos ("PALOMI TAS"): se prueban
    // también las parejas seguidas juntas.
    final sinVacias = lineKey(clave).split(' ');
    for (var i = 0; i + 1 < sinVacias.length; i++) {
      palabrasLinea.addAll(_palabras(sinVacias[i] + sinVacias[i + 1]));
    }
    if (palabrasLinea.isEmpty) return null;
    ({Category categoria, double cobertura})? mejorCompatible, mejorOtra;
    var evidenciaCompatible = 0.0, evidenciaOtra = 0.0;
    for (final (:categoria, :palabras) in _nombres) {
      var total = 0.0;
      var coincide = 0.0;
      var alguna = false;
      for (final palabra in palabras) {
        final idf = _idfPalabra[palabra]!;
        var parecido = 0.0;
        for (final p in palabrasLinea) {
          parecido = max(parecido, _parecidoPalabra(p, palabra));
        }
        if (parecido >= 0.8) alguna = true;
        total += idf;
        coincide += idf * parecido;
      }
      if (!alguna) continue;
      final cobertura = coincide / total;
      if (cobertura < 0.5) continue;
      final evidencia = coincide - 0.5 * (total - coincide);
      if (categoria.trackWeight == alPeso) {
        if (evidencia > evidenciaCompatible) {
          evidenciaCompatible = evidencia;
          mejorCompatible = (categoria: categoria, cobertura: cobertura);
        }
      } else if (evidencia > evidenciaOtra) {
        evidenciaOtra = evidencia;
        mejorOtra = (categoria: categoria, cobertura: cobertura * _factorPeso);
      }
    }
    return mejorCompatible ?? mejorOtra;
  }

  Map<String, double> _vector(Map<String, int> trigramas) {
    final vector = <String, double>{};
    var norma = 0.0;
    for (final e in trigramas.entries) {
      final peso = e.value * (_idfTrigrama[e.key] ?? log(_ejemplos.length + 1) + 1);
      vector[e.key] = peso;
      norma += peso * peso;
    }
    norma = sqrt(norma);
    if (norma == 0) return vector;
    return vector.map((k, v) => MapEntry(k, v / norma));
  }

  static double _coseno(Map<String, double> a, Map<String, double> b) {
    final (corto, largo) = a.length <= b.length ? (a, b) : (b, a);
    var suma = 0.0;
    for (final e in corto.entries) {
      final otro = largo[e.key];
      if (otro != null) suma += e.value * otro;
    }
    return suma;
  }
}

class _Ejemplo {
  _Ejemplo(this.linea, this.trigramas);

  final LearnedLine linea;
  final Map<String, int> trigramas;
  late Map<String, double> vector;
}

/// Trozos de tres letras de la clave, sin espacios: así da igual que el lector
/// parta una palabra en dos ("BANDE JA") o junte dos.
Map<String, int> _trigramas(String clave) {
  final texto = '^${clave.replaceAll(' ', '')}\$';
  final trigramas = <String, int>{};
  for (var i = 0; i + 3 <= texto.length; i++) {
    final g = texto.substring(i, i + 3);
    trigramas[g] = (trigramas[g] ?? 0) + 1;
  }
  return trigramas;
}

const _palabrasVacias = {'DE', 'DEL', 'LA', 'LAS', 'EL', 'LOS', 'CON', 'SIN', 'EN', 'AL', 'PARA', 'POR', 'Y'};

/// Palabras con significado, en singular aproximado ("TOMATES" → "TOMATE").
List<String> _palabras(String texto) => [
      for (final p in lineKey(texto).split(' '))
        if (p.length >= 2 && !_palabrasVacias.contains(p)) p.length > 3 && p.endsWith('S') ? p.substring(0, p.length - 1) : p,
    ];

/// De 0 a 1: igual, abreviada ("DETERG" por "DETERGENTE") o con alguna letra
/// mal leída ("OUESO" por "QUESO").
double _parecidoPalabra(String a, String b) {
  if (a == b) return 1;
  final (corta, larga) = a.length <= b.length ? (a, b) : (b, a);
  if (corta.length < 4) return 0;
  if (larga.startsWith(corta)) return 0.8;
  final ga = _trigramas(a), gb = _trigramas(b);
  var comunes = 0;
  for (final e in ga.entries) {
    comunes += min(e.value, gb[e.key] ?? 0);
  }
  final dice = 2 * comunes / (ga.values.fold(0, (s, v) => s + v) + gb.values.fold(0, (s, v) => s + v));
  return dice >= 0.55 ? dice : 0;
}
