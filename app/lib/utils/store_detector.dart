import '../models/store.dart';
import 'product_classifier.dart';
import 'text_normalizer.dart';

/// Cuántas líneas del principio del ticket se miran como cabecera: nombre del
/// comercio, razón social, dirección... Lo que viene después ya son productos.
const _lineasCabecera = 8;

/// Importe con dos decimales: la cabecera se da por terminada en la primera
/// línea que trae un precio.
final _importe = RegExp(r'\d{1,4}[.,]\s?\d{2}');

/// CIF ("F20033361", "F-20033361") o NIF de un autónomo ("12345678Z"), que es
/// lo que traen los franquiciados. Es lo más fiable de un ticket: no cambia
/// de una compra a otra y no se parece a ningún producto.
final _identificadorFiscal = RegExp(r'\b(?:([A-HJNPQRSUVW])[-. ]?(\d{7})([0-9A-J])|(\d{8})[-. ]?([A-Z]))\b');

/// Lo que identifica de qué tienda es un ticket sin depender de lo que se
/// compró: sus CIF/NIF (`CIF:...`) y las líneas de su cabecera (`CAB:...`),
/// ya reducidas con [lineKey] para que el número de ticket, la hora o un
/// carácter mal leído no las cambien.
///
/// Al guardar un ticket escaneado se apuntan con la tienda elegida, y la
/// próxima vez que salgan se pone esa tienda sola.
List<String> storeFingerprints(String rawText) {
  final huellas = <String>{};
  final texto = normalizeLine(rawText.replaceAll('\n', ' \n '));
  for (final m in _identificadorFiscal.allMatches(texto)) {
    final id = m[1] != null ? '${m[1]}${m[2]}${m[3]}' : '${m[4]}${m[5]}';
    huellas.add('CIF:$id');
  }

  for (final linea in _cabecera(rawText)) {
    final clave = lineKey(linea);
    // Lo muy corto ("A", "SL") no distingue a nadie.
    if (clave.replaceAll(' ', '').length >= 4) huellas.add('CAB:$clave');
  }
  return huellas.toList();
}

/// Las primeras líneas del ticket, hasta la primera que trae un precio.
Iterable<String> _cabecera(String rawText) => rawText
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .take(_lineasCabecera)
    .takeWhile((l) => !_importe.hasMatch(l));

/// Lo aprendido de una huella: en qué tienda se ha visto y cuántas veces.
class LearnedFingerprint {
  const LearnedFingerprint({required this.huella, required this.tienda, this.veces = 1});

  final String huella;
  final String tienda;
  final int veces;

  /// Id del documento en Firestore: una huella puede haberse visto en varias
  /// tiendas ("FACTURA SIMPLIFICADA" sale en todas), y cada pareja va aparte.
  static String docId(String huella, String tienda) {
    final id = '${huella}_${normalizeLine(tienda)}'.replaceAll(RegExp(r'[^A-Z0-9:_]+'), '_');
    return id.length <= 400 ? id : id.substring(0, 400);
  }
}

/// Adivina la tienda de un ticket escaneado entre las de la lista del hogar.
///
/// Primero por lo aprendido: cada huella del ticket vota por la tienda en la
/// que se ha visto (el CIF vale por tres líneas de cabecera). Las huellas que
/// han salido en más de una tienda no votan: son texto genérico de ticket.
///
/// Si no hay nada aprendido que encaje, busca el nombre de alguna tienda de la
/// lista escrito en el ticket ("EROSKI", "WWW.EROSKI.ES"...), y si tampoco, el
/// de alguna cadena conocida en la cabecera.
///
/// Devuelve el nombre tal y como está en la lista (o el de la cadena, si no
/// está), o `null` si no lo sabe.
String? detectStore(String rawText, {required List<Store> tiendas, List<LearnedFingerprint> aprendidas = const []}) {
  final porClave = {for (final t in tiendas) normalizeLine(t.nombre): t.nombre};

  final tiendasDeHuella = <String, Set<String>>{};
  for (final a in aprendidas) {
    final clave = normalizeLine(a.tienda);
    if (porClave.containsKey(clave)) tiendasDeHuella.putIfAbsent(a.huella, () => {}).add(clave);
  }
  final votos = <String, int>{};
  for (final huella in storeFingerprints(rawText)) {
    final candidatas = tiendasDeHuella[huella];
    if (candidatas == null || candidatas.length != 1) continue;
    votos[candidatas.single] = (votos[candidatas.single] ?? 0) + (huella.startsWith('CIF:') ? 3 : 1);
  }
  if (votos.isNotEmpty) {
    final orden = votos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (orden.length == 1 || orden[0].value > orden[1].value) return porClave[orden[0].key];
  }

  return _porNombre(rawText, porClave) ?? _porNombre(rawText, _cadenasConocidas, soloCabecera: true);
}

/// Cadenas que se reconocen aunque aún no estén en la lista del hogar: si el
/// ticket es de una de ellas, se propone con este nombre y al guardar se
/// añade a la lista. Solo cuentan en la cabecera, donde el ticket pone de qué
/// tienda es; más abajo el mismo nombre puede ser la marca de un producto.
const _cadenasConocidas = {
  'EROSKI': 'Eroski',
  'CAPRABO': 'Caprabo',
  'MERCADONA': 'Mercadona',
  'LIDL': 'Lidl',
  'ALDI': 'Aldi',
  'CARREFOUR': 'Carrefour',
  'ALCAMPO': 'Alcampo',
  'AUCHAN': 'Alcampo',
  'DIA': 'Día',
  'AHORRAMAS': 'Ahorramás',
  'CONSUM': 'Consum',
  'HIPERCOR': 'Hipercor',
  'SUPERCOR': 'Supercor',
  'EL CORTE INGLES': 'El Corte Inglés',
  'SPAR': 'Spar',
  'COVIRAN': 'Covirán',
  'GADIS': 'Gadis',
  'FROIZ': 'Froiz',
  'MASYMAS': 'Masymas',
  'BONPREU': 'Bonpreu',
  'CONDIS': 'Condis',
  'HIPERDINO': 'HiperDino',
  'FAMILY CASH': 'Family Cash',
  'SUPECO': 'Supeco',
  'MAKRO': 'Makro',
  'COSTCO': 'Costco',
  'PRIMOR': 'Primor',
  'DRUNI': 'Druni',
  'CLAREL': 'Clarel',
  'IKEA': 'Ikea',
  'DECATHLON': 'Decathlon',
  'LEROY MERLIN': 'Leroy Merlin',
  'PRIMARK': 'Primark',
};

/// La tienda de la lista cuyo nombre aparece en el ticket. En la cabecera
/// basta con 3 letras ("DIA"); en el resto hacen falta 5, para que una marca
/// corta dentro del nombre de un producto no se tome por la tienda. Si
/// encajan varias, la de nombre más largo: "Eroski City" antes que "Eroski".
String? _porNombre(String rawText, Map<String, String> porClave, {bool soloCabecera = false}) {
  String palabras(String s) => ' ${normalizeLine(s).replaceAll(RegExp(r'[^A-Z0-9]+'), ' ').trim()} ';
  final cabecera = palabras(_cabecera(rawText).join(' '));
  final todo = palabras(rawText);

  String? mejor;
  for (final clave in porClave.keys) {
    final nombre = palabras(clave);
    final letras = nombre.replaceAll(RegExp('[^A-Z]'), '').length;
    final aparece =
        (letras >= 3 && cabecera.contains(nombre)) || (!soloCabecera && letras >= 5 && todo.contains(nombre));
    if (aparece && (mejor == null || clave.length > mejor.length)) mejor = clave;
  }
  return mejor == null ? null : porClave[mejor];
}
