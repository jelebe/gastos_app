import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/category.dart';
import '../models/basket_inflation.dart';
import '../models/dashboard_summary.dart';
import '../models/product_summary.dart';
import '../models/settlement_balance.dart';
import '../models/store.dart';
import '../models/ticket_line_item.dart';
import '../models/transaction_summary.dart';
import '../utils/product_classifier.dart';
import '../utils/text_normalizer.dart';

/// Las dos personas del hogar. El orden importa solo aquí dentro: el saldo se
/// lleva en positivo a favor de la primera.
const personaA = 'Cano';
const personaB = 'Cana';

/// El valor de `pagadoPor` que significa "esto ya iba a medias": ninguno de
/// los dos adelantó nada por el otro, así que no mueve el saldo.
const pagadoPorAmbos = 'Ambos';

typedef TicketItemInput = ({String textoOriginal, double precioTotal, Category categoria, double? pesoGramos});

/// Lo que hay que aprender de una línea al guardar un ticket: su texto tal cual
/// salió del escáner, si iba al peso, y la categoría elegida (o
/// [LearnedLine.noProducto]).
typedef LineToLearn = ({String texto, bool alPeso, String decision});

/// Una línea de ticket ya guardada junto a los datos del ticket del que salió,
/// para poder listar "todo lo gastado en este grupo" sin perder de vista de
/// qué compra venía cada cosa.
typedef GroupLine = ({
  String textoOriginal,
  String? producto,
  String? categoriaId,
  double precio,
  double? pesoGramos,
  DateTime fecha,
  String? comercio,
  String? pagadoPor,
  bool compartido,
});

Map<String, dynamic> _itemData(TicketItemInput item) {
  final precioPorKilo = (item.categoria.trackWeight && item.pesoGramos != null && item.pesoGramos! > 0)
      ? item.precioTotal / (item.pesoGramos! / 1000)
      : null;
  return {
    'textoOriginal': item.textoOriginal,
    'categoriaId': item.categoria.id,
    'productoNormalizado': item.categoria.nombre,
    'precioTotal': item.precioTotal,
    'pesoGramos': item.pesoGramos,
    'precioPorKilo': precioPorKilo,
  };
}

/// La clave de mes natural ("AAAA-MM") a la que pertenece [fecha].
///
/// Es lo que se guarda en el campo `mes` de cada transacción, pero solo para
/// poder leerlo de un vistazo en la consola: al agrupar, lo que manda es el
/// mes contable, que se calcula de la fecha con [mesContableDe]. Si se
/// filtrara por este campo, cambiar el día de corte obligaría a reescribir
/// todos los documentos.
String mesDe(DateTime fecha) => '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

/// El primer día del mes que nombra una clave "AAAA-MM".
DateTime primerDiaDe(String mes) {
  final partes = mes.split('-');
  return DateTime(int.parse(partes[0]), int.parse(partes[1]));
}

/// El día del mes en que se da por hecho que cae la nómina cuando no hay
/// ninguna registrada de la que fiarse. Es el último recurso: solo se usa
/// mientras no se haya guardado ninguna.
const diaDeCorteDefecto = 25;

/// El día [dia] de ese mes sin pasarse de largo: un día 31 en un mes de 30 cae
/// el 30, y en febrero el 28. `DateTime` normaliza el día 0 al último del mes
/// anterior, así que el día 0 del siguiente es el último de este.
DateTime _diaDelMes(int year, int month, int dia) {
  final ultimo = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, dia < ultimo ? dia : ultimo);
}

/// La clave del mes siguiente a [mes].
String mesSiguienteDe(String mes) {
  final primero = primerDiaDe(mes);
  return mesDe(DateTime(primero.year, primero.month + 1));
}

/// La clave del mes anterior a [mes].
String mesAnteriorDe(String mes) {
  final primero = primerDiaDe(mes);
  return mesDe(DateTime(primero.year, primero.month - 1));
}

/// Si un ingreso de esta categoría es una nómina, que es lo que abre el mes.
/// Se compara sin tildes y en mayúsculas, así que valen "Nómina", "nomina" o
/// "Nómina de Cana".
bool esNominaCategoria(String? categoriaNombre) =>
    normalizeLine(categoriaNombre ?? '').contains('NOMINA');

/// El mes contable que abre una nómina cobrada el [fecha].
///
/// Si cae en la segunda mitad del mes, es la del mes siguiente: es el caso
/// normal, se cobra a final de mes y ese dinero es para el mes que entra. Si
/// cae en la primera, abre el mes en que se cobra: una nómina pagada con unos
/// días de retraso, ya entrado octubre, sigue siendo la que abre octubre.
String mesQueAbreLaNomina(DateTime fecha) =>
    fecha.day >= 15 ? mesDe(DateTime(fecha.year, fecha.month + 1)) : mesDe(fecha);

/// Dónde empieza cada mes contable: no el día 1, sino el día en que entró la
/// nómina que lo abre.
///
/// Si los dos cobran, manda la primera de las dos: el mes arranca cuando entra
/// el primer dinero. De los meses sin ninguna nómina guardada no hay forma de
/// saber el día, así que se estima con la nómina conocida más cercana (la
/// anterior; si no hay ninguna antes, la siguiente), quedándose con el día del
/// mes en que caía.
class MesesContables {
  const MesesContables(this._inicios);

  /// El reparto que sale de las fechas de las nóminas registradas, en
  /// cualquier orden.
  factory MesesContables.deNominas(Iterable<DateTime> fechas) {
    final inicios = <String, DateTime>{};
    for (final fecha in fechas) {
      final mes = mesQueAbreLaNomina(fecha);
      final actual = inicios[mes];
      if (actual == null || fecha.isBefore(actual)) inicios[mes] = fecha;
    }
    return MesesContables(inicios);
  }

  /// La nómina que abre cada mes contable, por clave "AAAA-MM". Solo están los
  /// meses de los que hay nómina guardada.
  final Map<String, DateTime> _inicios;

  /// Si [mes] arranca en una nómina de verdad, y no en una estimación.
  bool segunNomina(String mes) => _inicios.containsKey(mes);

  /// El momento en que empieza el mes contable [mes].
  ///
  /// De la nómina se toma solo el día, no la hora: lo gastado esa misma tarde
  /// tiene que entrar en el mes que abre.
  DateTime inicioDe(String mes) {
    final nomina = _inicios[mes];
    if (nomina != null) return DateTime(nomina.year, nomina.month, nomina.day);
    final (mesRelativo, dia) = _aperturaEstimada(mes);
    final primero = primerDiaDe(mes);
    return _diaDelMes(primero.year, primero.month + mesRelativo, dia);
  }

  /// El tramo de fechas del mes contable [mes]: de [desde] (incluido) a donde
  /// arranca el siguiente, [hasta] (excluido).
  ({DateTime desde, DateTime hasta}) tramoDe(String mes) =>
      (desde: inicioDe(mes), hasta: inicioDe(mesSiguienteDe(mes)));

  /// En qué mes contable cae [fecha].
  ///
  /// Un mes siempre arranca alrededor del cambio de mes natural (de la segunda
  /// mitad del anterior a la primera de este), así que solo hay tres
  /// candidatos y basta con ver de cuál ha pasado ya.
  String mesContableDe(DateTime fecha) {
    final propio = mesDe(fecha);
    final siguiente = mesSiguienteDe(propio);
    if (!fecha.isBefore(inicioDe(siguiente))) return siguiente;
    if (!fecha.isBefore(inicioDe(propio))) return propio;
    return mesAnteriorDe(propio);
  }

  /// Con qué día se estima el arranque de un mes sin nómina: el de la conocida
  /// más cercana, diciendo además si caía en el mes anterior (lo normal) o ya
  /// en el propio.
  (int mesRelativo, int dia) _aperturaEstimada(String mes) {
    String? anterior, siguiente;
    for (final clave in _inicios.keys) {
      // Las claves "AAAA-MM" se ordenan igual como texto que como fecha.
      if (clave.compareTo(mes) < 0) {
        if (anterior == null || clave.compareTo(anterior) > 0) anterior = clave;
      } else if (clave.compareTo(mes) > 0) {
        if (siguiente == null || clave.compareTo(siguiente) < 0) siguiente = clave;
      }
    }
    final referencia = anterior ?? siguiente;
    if (referencia == null) return (-1, diaDeCorteDefecto);
    final nomina = _inicios[referencia]!;
    return (mesDe(nomina) == referencia ? 0 : -1, nomina.day);
  }
}

List<MapEntry<String, double>> _ordenadoPorImporte(Map<String, double> totales, {bool quitarVacios = false}) {
  final entradas = totales.entries.toList();
  if (quitarVacios) entradas.removeWhere((e) => e.value <= 0);
  entradas.sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in entradas) MapEntry(e.key, e.value)];
}

/// Un movimiento reducido a lo único que importa para el saldo: quién puso el
/// dinero y cuánto. Separarlo de Firestore es lo que permite probar el
/// cálculo sin levantar nada.
typedef MovimientoSaldo = ({String tipo, String? quienPaga, double importe, bool compartido, DateTime fecha});

/// El saldo que dejan estos movimientos.
///
/// La idea es que cada gasto compartido lo adelanta uno solo pero les toca a
/// los dos: quien paga pone de más la mitad, que es justo lo que el otro le
/// debe. Lo personal es de quien lo paga y no entra. Lo pagado por
/// [pagadoPorAmbos] ya iba a medias, así que tampoco mueve nada. Y devolver
/// dinero (una liquidación) cuenta igual que adelantarlo, por el importe
/// entero: por eso saldar la deuda la deja exactamente a cero.
SettlementBalance balanceDe(Iterable<MovimientoSaldo> movimientos) {
  // En positivo, lo que [personaA] ha puesto de más.
  var saldo = 0.0;
  var gastos = 0;
  DateTime? ultima;

  for (final m in movimientos) {
    final signo = switch (m.quienPaga) {
      personaA => 1,
      personaB => -1,
      // [pagadoPorAmbos], o un movimiento viejo sin quién pagó: no hay nadie
      // que haya adelantado nada por el otro.
      _ => 0,
    };
    if (signo == 0) continue;

    switch (m.tipo) {
      case 'gasto':
        if (!m.compartido) continue;
        saldo += signo * m.importe / 2;
        gastos++;
      case 'liquidacion':
        saldo += signo * m.importe;
        if (ultima == null || m.fecha.isAfter(ultima)) ultima = m.fecha;
    }
  }

  final aFavorDeA = saldo >= 0;
  return SettlementBalance(
    acreedor: aFavorDeA ? personaA : personaB,
    deudor: aFavorDeA ? personaB : personaA,
    importe: saldo.abs(),
    gastosContados: gastos,
    ultimaLiquidacion: ultima,
  );
}

/// Punto de acceso único al hogar del usuario actual: su documento, sus
/// categorías y lo aprendido de sus tickets (`lineasAprendidas`).
class HouseholdRepository {
  DocumentReference<Map<String, dynamic>>? _householdRef;

  Future<DocumentReference<Map<String, dynamic>>> get householdRef async {
    final cached = _householdRef;
    if (cached != null) return cached;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('households')
        .where('members', arrayContains: uid)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      throw StateError('Este usuario no pertenece a ningún hogar todavía.');
    }
    _householdRef = snapshot.docs.first.reference;
    return _householdRef!;
  }

  MesesContables? _meses;

  /// Cómo se reparten los meses contables en este hogar.
  ///
  /// Se cachea porque lo mira cada consulta del resumen, y se tira al guardar
  /// o borrar cualquier movimiento: una nómina nueva mueve los límites.
  Future<MesesContables> loadMesesContables() async {
    final cached = _meses;
    if (cached != null) return cached;

    final household = await householdRef;
    final snap = await household.collection('transactions').where('tipo', isEqualTo: 'ingreso').get();
    final nominas = <DateTime>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (!esNominaCategoria(data['categoriaNombre'] as String?)) continue;
      final fecha = (data['fecha'] as Timestamp?)?.toDate();
      if (fecha != null) nominas.add(fecha);
    }
    return _meses = MesesContables.deNominas(nominas);
  }

  Future<CollectionReference<Map<String, dynamic>>> get _categoriesCol async =>
      (await householdRef).collection('categories');

  Stream<List<Category>> watchCategories() {
    return Stream.fromFuture(_categoriesCol).asyncExpand(
      (col) => col.orderBy('grupo').orderBy('nombre').snapshots().map(
            (snap) => snap.docs.map((d) => Category.fromFirestore(d.id, d.data())).toList(),
          ),
    );
  }

  Future<List<Category>> loadCategories() async {
    final col = await _categoriesCol;
    final snap = await col.orderBy('grupo').orderBy('nombre').get();
    return snap.docs.map((d) => Category.fromFirestore(d.id, d.data())).toList();
  }

  Future<CollectionReference<Map<String, dynamic>>> get _comerciosCol async =>
      (await householdRef).collection('comercios');

  /// Los establecimientos del hogar, por orden alfabético.
  Stream<List<Store>> watchStores() {
    return Stream.fromFuture(_comerciosCol).asyncExpand(
      (col) => col.orderBy('nombre').snapshots().map(
            (snap) => snap.docs.map((d) => Store.fromFirestore(d.id, d.data())).toList(),
          ),
    );
  }

  /// Los establecimientos del hogar, rellenando la lista la primera vez con
  /// los que ya se hubieran escrito a mano en tickets anteriores.
  Future<List<Store>> loadStores() async {
    await (_migracionComercios ??= _migrarComercios().catchError((Object e) {
      _migracionComercios = null; // que lo reintente la próxima vez
      throw e;
    }));
    final snap = await (await _comerciosCol).orderBy('nombre').get();
    return snap.docs.map((d) => Store.fromFirestore(d.id, d.data())).toList();
  }

  Future<void>? _migracionComercios;

  /// La primera vez, siembra la lista con los comercios que ya estuvieran
  /// escritos en los tickets: si no, al estrenar el selector estaría vacío y
  /// habría que volver a teclear lo que ya se había teclado.
  ///
  /// De cada nombre repetido se queda el que más veces se haya escrito, que es
  /// el que probablemente esté bien puesto.
  Future<void> _migrarComercios() async {
    final household = await householdRef;
    final hogar = await household.get();
    if (hogar.data()?['comerciosMigrados'] == true) return;

    final snap = await household.collection('transactions').get();
    final veces = <String, Map<String, int>>{};
    for (final doc in snap.docs) {
      final nombre = (doc.data()['comercio'] as String?)?.trim();
      if (nombre == null || nombre.isEmpty) continue;
      final clave = normalizeLine(nombre);
      if (clave.isEmpty) continue;
      veces.putIfAbsent(clave, () => {})[nombre] = (veces[clave]![nombre] ?? 0) + 1;
    }

    final col = household.collection('comercios');
    final batch = FirebaseFirestore.instance.batch();
    for (final variantes in veces.values) {
      final masUsado = variantes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      batch.set(col.doc(), {'nombre': masUsado});
    }
    batch.set(household, {'comerciosMigrados': true}, SetOptions(merge: true));
    await batch.commit();
  }

  /// Añade un establecimiento, o devuelve el que ya hubiera con ese nombre.
  ///
  /// La comparación va normalizada (sin tildes ni mayúsculas), que es justo el
  /// problema que la lista viene a resolver: "Mercadona", "mercadona" y
  /// "MERCADONA" son el mismo sitio.
  Future<Store> createStore(String nombre, {String? grupo}) async {
    final limpio = nombre.trim();
    final grupoLimpio = grupo?.trim();
    final clave = normalizeLine(limpio);
    final col = await _comerciosCol;

    for (final doc in (await col.get()).docs) {
      final existente = Store.fromFirestore(doc.id, doc.data());
      if (normalizeLine(existente.nombre) == clave) return existente;
    }
    final datos = {'nombre': limpio, if (grupoLimpio != null && grupoLimpio.isNotEmpty) 'grupo': grupoLimpio};
    final ref = await col.add(datos);
    return Store(id: ref.id, nombre: limpio, grupo: grupoLimpio);
  }

  /// Mete varias tiendas en un grupo de una vez, o las saca de él con [grupo]
  /// nulo. Es lo que hace llevadero colocar una lista que ya venía hecha.
  Future<void> setStoreGroup(Iterable<String> ids, String? grupo) async {
    final col = await _comerciosCol;
    final limpio = grupo?.trim();
    final valor = (limpio == null || limpio.isEmpty) ? FieldValue.delete() : limpio;
    final lista = ids.toList();
    for (var i = 0; i < lista.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in lista.skip(i).take(400)) {
        batch.update(col.doc(id), {'grupo': valor});
      }
      await batch.commit();
    }
  }

  /// Quita un establecimiento de la lista. Los tickets ya guardados no se ven
  /// afectados: cada uno guarda el nombre, no una referencia.
  Future<void> deleteStore(String id) async {
    await (await _comerciosCol).doc(id).delete();
  }

  /// Quita varios de una vez. Para dejar la lista limpia de lo que nunca fue
  /// una tienda hay que poder hacerlo en una tacada, no de uno en uno.
  Future<void> deleteStores(Iterable<String> ids) async {
    final col = await _comerciosCol;
    final lista = ids.toList();
    for (var i = 0; i < lista.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in lista.skip(i).take(400)) {
        batch.delete(col.doc(id));
      }
      await batch.commit();
    }
  }

  /// Cambia el nombre de una tienda y, con él, el de los tickets que la traían.
  ///
  /// Si ya hay otra con ese nombre las fusiona: los tickets pasan a la que se
  /// queda y la renombrada desaparece de la lista. Es como se arreglan los
  /// duplicados que entraron al sembrarla ("Ahorramás" y "Ahorramás a0"), y
  /// por eso toca los tickets: si solo cambiara la lista, el histórico seguiría
  /// partido en dos y la comparativa de precios también.
  ///
  /// Devuelve cuántos tickets se han reetiquetado.
  Future<int> renameStore(String id, String nuevoNombre, {String? grupo}) async {
    final limpio = nuevoNombre.trim();
    final grupoLimpio = grupo?.trim();
    if (limpio.isEmpty) throw ArgumentError('El nombre no puede estar vacío.');

    final household = await householdRef;
    final col = household.collection('comercios');
    final doc = await col.doc(id).get();
    final anterior = (doc.data()?['nombre'] as String?)?.trim();
    if (anterior == null) throw StateError('Esa tienda ya no está en la lista.');

    final clave = normalizeLine(limpio);
    String? idQueSeQueda;
    for (final otra in (await col.get()).docs) {
      if (otra.id == id) continue;
      if (normalizeLine(otra.data()['nombre'] as String? ?? '') == clave) {
        idQueSeQueda = otra.id;
        break;
      }
    }

    // Los tickets guardan el nombre, así que se buscan por él.
    final tickets = await household.collection('transactions').where('comercio', isEqualTo: anterior).get();
    for (var i = 0; i < tickets.docs.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final tx in tickets.docs.skip(i).take(400)) {
        batch.update(tx.reference, {'comercio': limpio});
      }
      await batch.commit();
    }

    // Si ya había otra con ese nombre, esta sobra; si no, se queda con el
    // nombre nuevo. En los dos casos manda el grupo que se acaba de elegir,
    // que es lo último que ha dicho quien lo edita.
    final grupoData = {
      'grupo': (grupoLimpio == null || grupoLimpio.isEmpty) ? FieldValue.delete() : grupoLimpio,
    };
    if (idQueSeQueda != null) {
      await col.doc(idQueSeQueda).update(grupoData);
      await col.doc(id).delete();
    } else {
      await col.doc(id).update({'nombre': limpio, ...grupoData});
    }
    return tickets.docs.length;
  }

  Future<CollectionReference<Map<String, dynamic>>> get _aprendidasCol async =>
      (await householdRef).collection('lineasAprendidas');

  Future<List<LearnedLine>>? _migracion;

  /// Todo lo aprendido de los tickets guardados, para [ProductClassifier].
  Future<List<LearnedLine>> loadLearnedLines() async {
    final migradas = await (_migracion ??= _migrarAprendizaje().catchError((Object e) {
      _migracion = null; // que lo vuelva a intentar la próxima vez
      throw e;
    }));
    final snap = await (await _aprendidasCol).get();
    final lineas = <String, LearnedLine>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final clave = data['clave'], decision = data['decision'];
      if (clave is! String || decision is! String) continue;
      lineas[doc.id] = LearnedLine(
        clave: clave,
        alPeso: data['alPeso'] == true,
        decision: decision,
        veces: (data['veces'] as num?)?.toInt() ?? 1,
      );
    }
    // Si la migración acaba de hacerse y sus escrituras aún no han llegado
    // (p.ej. sin conexión), se usa lo calculado en memoria.
    for (final linea in migradas) {
      lineas.putIfAbsent(LearnedLine.docId(linea.clave, linea.alPeso), () => linea);
    }
    return lineas.values.toList();
  }

  /// Apunta lo decidido para estas líneas al guardar un ticket: su categoría
  /// o que no eran productos. Si una misma línea ya estaba aprendida con otra
  /// decisión, manda la nueva: así se corrigen los errores.
  Future<void> learnLines(Iterable<LineToLearn> lineas) async {
    final col = await _aprendidasCol;
    final porDocumento = <String, (String clave, LineToLearn linea)>{};
    for (final linea in lineas) {
      final clave = lineKey(linea.texto);
      if (clave.isEmpty) continue;
      porDocumento[LearnedLine.docId(clave, linea.alPeso)] = (clave, linea);
    }
    final entradas = porDocumento.entries.toList();
    for (var i = 0; i < entradas.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final MapEntry(key: id, value: (clave, linea)) in entradas.skip(i).take(400)) {
        batch.set(
          col.doc(id),
          {
            'clave': clave,
            'alPeso': linea.alPeso,
            'decision': linea.decision,
            'veces': FieldValue.increment(1),
            'actualizado': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  /// La primera vez, rellena lo aprendido con lo que ya había: el diccionario
  /// de alias antiguo y las líneas de todos los tickets guardados (estas
  /// después, del más antiguo al más reciente, para que mande lo último).
  /// Devuelve lo calculado; si ya estaba hecho, nada.
  ///
  /// Las escrituras no se esperan: sin conexión se quedarían colgadas hasta
  /// recuperarla y bloquearían el escaneo. Firestore las manda cuando puede.
  Future<List<LearnedLine>> _migrarAprendizaje() async {
    final household = await householdRef;
    final hogar = await household.get();
    if (hogar.data()?['aprendizajeMigrado'] == true) return const [];

    final categorias = {for (final c in await loadCategories()) c.id: c};
    final lineas = <String, LearnedLine>{};
    void anota(Object? texto, bool alPeso, Object? categoriaId) {
      if (texto is! String || categoriaId is! String || !categorias.containsKey(categoriaId)) return;
      final clave = lineKey(texto);
      if (clave.isEmpty) return;
      final id = LearnedLine.docId(clave, alPeso);
      lineas[id] = LearnedLine(clave: clave, alPeso: alPeso, decision: categoriaId, veces: (lineas[id]?.veces ?? 0) + 1);
    }

    // Los alias no guardaban si iba al peso: se toma el de su categoría.
    for (final alias in (await household.collection('productAliases').get()).docs) {
      final categoriaId = alias.data()['categoriaId'];
      for (final texto in alias.data()['textosOriginales'] as List? ?? const []) {
        anota(texto, categorias[categoriaId]?.trackWeight ?? false, categoriaId);
      }
    }
    final tickets = (await household.collection('transactions').where('tipo', isEqualTo: 'gasto').get()).docs
      ..sort((a, b) => ((a.data()['fecha'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
          .compareTo((b.data()['fecha'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    final lineasPorTicket = await Future.wait(tickets.map((t) => t.reference.collection('items').get()));
    for (final items in lineasPorTicket) {
      for (final item in items.docs) {
        anota(item.data()['textoOriginal'], item.data()['pesoGramos'] != null, item.data()['categoriaId']);
      }
    }

    final col = household.collection('lineasAprendidas');
    final entradas = lineas.entries.toList();
    for (var i = 0; i < entradas.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final MapEntry(key: id, value: linea) in entradas.skip(i).take(400)) {
        batch.set(col.doc(id), {
          'clave': linea.clave,
          'alPeso': linea.alPeso,
          'decision': linea.decision,
          'veces': linea.veces,
          'actualizado': FieldValue.serverTimestamp(),
        });
      }
      batch.commit().ignore();
    }
    household.update({'aprendizajeMigrado': true}).ignore();
    return lineas.values.toList();
  }

  Future<Category> createCategory({
    required String grupo,
    required String nombre,
    required String tipo,
    required bool trackWeight,
    required String unidadDefault,
  }) async {
    final col = await _categoriesCol;
    final data = {
      'grupo': grupo,
      'nombre': nombre,
      'tipo': tipo,
      'trackWeight': trackWeight,
      'unidadDefault': unidadDefault,
    };
    final ref = await col.add(data);
    return Category.fromFirestore(ref.id, data);
  }

  /// Borra una categoría. Los tickets ya guardados no se ven afectados: cada
  /// línea guarda su propio nombre de categoría en el momento de guardar, no
  /// una referencia viva. Lo aprendido que apuntaba a ella deja de usarse
  /// (el clasificador ignora las categorías que ya no existen).
  Future<void> deleteCategory(String categoryId) async {
    final col = await _categoriesCol;
    await col.doc(categoryId).delete();
  }

  Future<void> saveTicket({
    required List<TicketItemInput> items,
    required double importeTotal,
    String? comercio,
    required DateTime fecha,
    String? nota,
    required String pagadoPor,
    bool compartido = true,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final household = await householdRef;
    final mes = mesDe(fecha);

    final transactionRef = await household.collection('transactions').add({
      'tipo': 'gasto',
      'origen': 'ticket',
      'fecha': Timestamp.fromDate(fecha),
      'mes': mes,
      'comercio': comercio,
      'importeTotal': importeTotal,
      'nota': (nota == null || nota.trim().isEmpty) ? null : nota.trim(),
      'pagadoPor': pagadoPor,
      'compartido': compartido,
      'moneda': 'EUR',
      'creadoPor': uid,
    });

    final batch = FirebaseFirestore.instance.batch();
    final itemsCol = transactionRef.collection('items');
    for (final item in items) {
      batch.set(itemsCol.doc(), _itemData(item));
    }
    await batch.commit();
  }

  /// Sustituye un ticket ya guardado: actualiza sus datos y reemplaza todas
  /// sus líneas por las nuevas (se borran las antiguas y se escriben las
  /// actuales, en vez de intentar casar una a una).
  Future<void> updateTicket({
    required String transactionId,
    required List<TicketItemInput> items,
    required double importeTotal,
    String? comercio,
    required DateTime fecha,
    String? nota,
    required String pagadoPor,
    bool compartido = true,
  }) async {
    final household = await householdRef;
    final mes = mesDe(fecha);
    final transactionRef = household.collection('transactions').doc(transactionId);

    await transactionRef.update({
      'fecha': Timestamp.fromDate(fecha),
      'mes': mes,
      'comercio': comercio,
      'importeTotal': importeTotal,
      'nota': (nota == null || nota.trim().isEmpty) ? null : nota.trim(),
      'pagadoPor': pagadoPor,
      'compartido': compartido,
    });

    final itemsCol = transactionRef.collection('items');
    final existing = await itemsCol.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    for (final item in items) {
      batch.set(itemsCol.doc(), _itemData(item));
    }
    await batch.commit();
  }

  /// Líneas de un ticket ya guardado, para reabrirlo en la pantalla de
  /// confirmación y poder editarlo.
  Future<List<TicketLineItem>> loadTicketItems(String transactionId, List<Category> categories) async {
    final household = await householdRef;
    final itemsSnap = await household.collection('transactions').doc(transactionId).collection('items').get();
    final categoriaPorId = {for (final c in categories) c.id: c};

    return itemsSnap.docs.map((d) {
      final data = d.data();
      final categoriaId = data['categoriaId'] as String?;
      final categoria = categoriaId != null ? categoriaPorId[categoriaId] : null;
      return TicketLineItem(
        textoOriginal: data['textoOriginal'] as String? ?? '',
        precioTotal: (data['precioTotal'] as num?)?.toDouble(),
        categoriaId: categoriaId,
        grupo: categoria?.grupo,
        productoNormalizado: data['productoNormalizado'] as String?,
        trackWeight: categoria?.trackWeight ?? false,
        pesoGramos: (data['pesoGramos'] as num?)?.toDouble(),
        alPeso: data['pesoGramos'] != null,
      );
    }).toList();
  }

  /// Registra un ingreso suelto (nómina, venta, devolución...): a diferencia
  /// de un ticket, es una única cantidad con una sola categoría, sin líneas.
  Future<void> saveIncome({
    required Category categoria,
    required double importe,
    required DateTime fecha,
    String? nota,
    required String pagadoPor,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final household = await householdRef;
    final mes = mesDe(fecha);

    await household.collection('transactions').add({
      'tipo': 'ingreso',
      'origen': 'manual',
      'fecha': Timestamp.fromDate(fecha),
      'mes': mes,
      'categoriaId': categoria.id,
      'categoriaNombre': categoria.nombre,
      'nota': (nota == null || nota.trim().isEmpty) ? null : nota.trim(),
      'pagadoPor': pagadoPor,
      'importeTotal': importe,
      'moneda': 'EUR',
      'creadoPor': uid,
    });
    _meses = null; // si era una nómina, mueve los límites de los meses
  }

  /// Sustituye los datos de un ingreso ya guardado.
  Future<void> updateIncome({
    required String id,
    required Category categoria,
    required double importe,
    required DateTime fecha,
    String? nota,
    required String pagadoPor,
  }) async {
    final household = await householdRef;
    final mes = mesDe(fecha);
    await household.collection('transactions').doc(id).update({
      'fecha': Timestamp.fromDate(fecha),
      'mes': mes,
      'categoriaId': categoria.id,
      'categoriaNombre': categoria.nombre,
      'nota': (nota == null || nota.trim().isEmpty) ? null : nota.trim(),
      'pagadoPor': pagadoPor,
      'importeTotal': importe,
    });
    _meses = null; // si era una nómina, mueve los límites de los meses
  }

  /// Cómo van las cuentas entre los dos ahora mismo.
  ///
  /// Se recorre todo el histórico, no solo un mes: una deuda no caduca porque
  /// cambie el mes. Solo se leen las transacciones, nunca sus líneas, que es
  /// lo caro; quién pagó y si es compartido son datos del ticket entero.
  Future<SettlementBalance> loadBalance() async {
    final household = await householdRef;
    final snap = await household.collection('transactions').get();

    final movimientos = <MovimientoSaldo>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      movimientos.add((
        tipo: data['tipo'] as String? ?? '',
        // Una liquidación guarda de quién sale el dinero en `de`; un gasto,
        // en `pagadoPor`.
        quienPaga: (data['de'] ?? data['pagadoPor']) as String?,
        importe: (data['importeTotal'] as num?)?.toDouble() ?? 0,
        // Los tickets de antes de que existiera el campo son compartidos,
        // igual que en [TransactionSummary].
        compartido: data['compartido'] as bool? ?? true,
        fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime(1970),
      ));
    }
    return balanceDe(movimientos);
  }

  /// Apunta que [de] le ha pasado [importe] a [para].
  ///
  /// No es un gasto ni un ingreso: la casa no gasta ni ingresa nada cuando el
  /// dinero cambia de bolsillo, así que no entra en ningún total del resumen.
  /// Lo único que hace es mover la deuda, y en qué dirección depende de quién
  /// pone el dinero: el que lo pone queda a favor.
  ///
  /// [concepto] no cambia las cuentas, solo cómo se lee después: saldar una
  /// deuda y prestar dinero son la misma operación con el signo al revés.
  Future<void> saveSettlement({
    required String de,
    required String para,
    required double importe,
    required DateTime fecha,
    String concepto = conceptoSaldar,
    String? nota,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final household = await householdRef;

    await household.collection('transactions').add({
      'tipo': 'liquidacion',
      'origen': 'manual',
      'fecha': Timestamp.fromDate(fecha),
      'mes': mesDe(fecha),
      'de': de,
      'para': para,
      'concepto': concepto,
      // También como `pagadoPor`, que es lo que miran las listas y los
      // filtros por persona que ya existen.
      'pagadoPor': de,
      'importeTotal': importe,
      'nota': (nota == null || nota.trim().isEmpty) ? null : nota.trim(),
      'moneda': 'EUR',
      'creadoPor': uid,
    });
  }

  /// Gastos o ingresos ya guardados (según [tipo]), del más reciente al más
  /// antiguo. Se ordena en el cliente para no depender de un índice
  /// compuesto en Firestore.
  ///
  /// Con los gastos van también las liquidaciones: es dinero que sale del
  /// bolsillo de uno, y si no se listaran aquí no habría dónde verlas ni
  /// cómo borrar una apuntada por error. Eso sí, no suman en el total: lo
  /// que la casa gastó ya se contó cuando se registró el ticket.
  Stream<List<TransactionSummary>> watchTransactions(String tipo) {
    final tipos = tipo == 'gasto' ? const ['gasto', 'liquidacion'] : [tipo];
    return Stream.fromFuture(householdRef).asyncExpand(
      (ref) => ref.collection('transactions').where('tipo', whereIn: tipos).snapshots().map((snap) {
        final list = snap.docs.map((d) => TransactionSummary.fromFirestore(d.id, d.data())).toList();
        list.sort((a, b) => b.fecha.compareTo(a.fecha));
        return list;
      }),
    );
  }

  /// Borra un gasto o ingreso ya guardado (y sus líneas, si las tiene).
  Future<void> deleteTransaction(String id) async {
    final household = await householdRef;
    final ref = household.collection('transactions').doc(id);
    final items = await ref.collection('items').get();
    if (items.docs.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in items.docs) {
        batch.delete(item.reference);
      }
      batch.delete(ref);
      await batch.commit();
    } else {
      await ref.delete();
    }
    _meses = null; // si era una nómina, mueve los límites de los meses
  }

  /// Los últimos [limit] movimientos (gastos e ingresos mezclados), para el
  /// resumen de la pantalla de inicio.
  Stream<List<TransactionSummary>> watchRecentTransactions({int limit = 5}) {
    return Stream.fromFuture(householdRef).asyncExpand(
      (ref) => ref
          .collection('transactions')
          .orderBy('fecha', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map((d) => TransactionSummary.fromFirestore(d.id, d.data())).toList()),
    );
  }

  /// El mes contable en el que estamos ahora mismo. No es el del calendario:
  /// hoy puede ser 30 de septiembre y, si la nómina entró el 29, estar ya en
  /// octubre.
  Future<String> mesEnCurso() async => (await loadMesesContables()).mesContableDe(DateTime.now());

  /// Todo lo que enseña la pantalla de inicio del mes contable [mes]
  /// ("AAAA-MM"), o del mes en curso si es nulo, con la tendencia de los
  /// [months] meses que acaban en él.
  ///
  /// Los meses no son los del calendario: empiezan el día de corte del mes
  /// anterior (ver [mesContableDe]), así que la consulta va por tramo de
  /// fechas.
  ///
  /// Sale de una única consulta por esa ventana: dentro de ella están
  /// tanto el mes elegido (para los desgloses) como el anterior (para la
  /// comparación), así que no hace falta volver a Firestore una vez por
  /// bloque. Solo se bajan las líneas de los tickets de esos dos meses, que
  /// son los únicos que se desglosan por categoría; del resto de la ventana
  /// basta el importe total de cada ticket.
  Future<DashboardSummary> loadDashboardSummary(String? mesPedido, {int months = 6}) async {
    final household = await householdRef;
    final contables = await loadMesesContables();
    final mesAhora = contables.mesContableDe(DateTime.now());
    final mes = mesPedido ?? mesAhora;
    final fechaMes = primerDiaDe(mes);
    final mesAnterior = mesDe(DateTime(fechaMes.year, fechaMes.month - 1));
    final meses = List.generate(
      months,
      (i) => mesDe(DateTime(fechaMes.year, fechaMes.month - (months - 1 - i))),
    );
    final tramo = contables.tramoDe(mes);
    // Con months = 1 el mes anterior se queda fuera de la serie, pero la
    // comparación lo sigue necesitando: la ventana arranca en el más antiguo
    // de los dos.
    final inicioPrimero = contables.inicioDe(meses.first);
    final inicioAnterior = contables.inicioDe(mesAnterior);
    final desde = inicioPrimero.isBefore(inicioAnterior) ? inicioPrimero : inicioAnterior;

    final categorias = await loadCategories();
    final grupoPorCategoriaId = {for (final c in categorias) c.id: c.grupo};

    final txSnap = await household
        .collection('transactions')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('fecha', isLessThan: Timestamp.fromDate(tramo.hasta))
        .get();

    /// En qué mes contable cae un documento, que es lo que decide en qué
    /// bloque del resumen entra.
    String mesContableDelDoc(Map<String, dynamic> data) =>
        contables.mesContableDe((data['fecha'] as Timestamp).toDate());

    // Los tickets cuyas líneas hacen falta: los del mes que se mira y los del
    // anterior. Se leen todos a la vez, no uno detrás de otro.
    final docsConLineas = txSnap.docs.where((d) {
      final data = d.data();
      if (data['tipo'] != 'gasto') return false;
      final mesDoc = mesContableDelDoc(data);
      return mesDoc == mes || mesDoc == mesAnterior;
    }).toList();
    final itemsSnaps = await Future.wait(docsConLineas.map((d) => d.reference.collection('items').get()));

    final gastosPorMes = {for (final m in meses) m: 0.0};
    final ingresosPorMes = {for (final m in meses) m: 0.0};
    final porPersona = <String, double>{};
    final totalPorPersona = {'Cano': 0.0, 'Cana': 0.0};

    for (final doc in txSnap.docs) {
      final data = doc.data();
      final mesDoc = mesContableDelDoc(data);
      final importe = (data['importeTotal'] as num).toDouble();
      final tipo = data['tipo'];
      // Una liquidación solo mueve dinero de un bolsillo al otro: ni se ha
      // gastado ni se ha ingresado nada, así que no entra en ningún total.
      if (tipo != 'gasto' && tipo != 'ingreso') continue;
      final esGasto = tipo == 'gasto';

      final serie = esGasto ? gastosPorMes : ingresosPorMes;
      if (serie.containsKey(mesDoc)) serie[mesDoc] = serie[mesDoc]! + importe;
      if (!esGasto || mesDoc != mes) continue;

      // Reparto del gasto compartido: uno marcado como personal (un capricho
      // que no se reparte) no debe distorsionar quién ha puesto más dinero
      // para la casa, así que no cuenta aquí.
      if (data['compartido'] != false) {
        final persona = data['pagadoPor'] as String? ?? 'Sin especificar';
        porPersona[persona] = (porPersona[persona] ?? 0) + importe;
      }
      // El total de cada uno sí cuenta lo personal, y lo pagado por "Ambos"
      // se reparte a partes iguales.
      final persona = data['pagadoPor'] as String?;
      if (persona == 'Ambos') {
        totalPorPersona['Cano'] = totalPorPersona['Cano']! + importe / 2;
        totalPorPersona['Cana'] = totalPorPersona['Cana']! + importe / 2;
      } else if (totalPorPersona.containsKey(persona)) {
        totalPorPersona[persona!] = totalPorPersona[persona]! + importe;
      }
    }

    final gastoPorGrupo = <String, double>{};
    final gastoPorGrupoAnterior = <String, double>{};
    for (var i = 0; i < docsConLineas.length; i++) {
      final esDelMes = mesContableDelDoc(docsConLineas[i].data()) == mes;
      final destino = esDelMes ? gastoPorGrupo : gastoPorGrupoAnterior;
      for (final itemDoc in itemsSnaps[i].docs) {
        final data = itemDoc.data();
        final grupo = grupoPorCategoriaId[data['categoriaId'] as String?] ?? 'Sin categoría';
        destino[grupo] = (destino[grupo] ?? 0) + ((data['precioTotal'] as num?)?.toDouble() ?? 0);
      }
    }

    final comparacion = [
      for (final grupo in {...gastoPorGrupo.keys, ...gastoPorGrupoAnterior.keys})
        (
          grupo: grupo,
          actual: gastoPorGrupo[grupo] ?? 0.0,
          anterior: gastoPorGrupoAnterior[grupo] ?? 0.0,
        ),
    ]..sort((a, b) => b.actual.compareTo(a.actual));

    return DashboardSummary(
      mes: mes,
      esMesEnCurso: mes == mesAhora,
      gastosPorMes: [for (final m in meses) MapEntry(m, gastosPorMes[m]!)],
      ingresosPorMes: [for (final m in meses) MapEntry(m, ingresosPorMes[m]!)],
      categoryBreakdown: _ordenadoPorImporte(gastoPorGrupo),
      categoryComparison: comparacion,
      personBreakdown: _ordenadoPorImporte(porPersona),
      personTotalSpending: _ordenadoPorImporte(totalPorPersona, quitarVacios: true),
      desde: tramo.desde,
      hasta: tramo.hasta,
      inicioSegunNomina: contables.segunNomina(mes),
    );
  }

  /// Todas las líneas de gasto del mes [mes] ("AAAA-MM") que pertenecen al
  /// grupo de categoría [grupo], de la más reciente a la más antigua. Es el
  /// detalle que hay detrás de cada tramo del desglose por categoría de
  /// [loadDashboardSummary]: las líneas sin categoría conocida caen en "Sin
  /// categoría", igual que allí.
  Future<List<GroupLine>> loadGroupLines(String mes, String grupo) async {
    final household = await householdRef;
    final categorias = await loadCategories();
    final grupoPorCategoriaId = {for (final c in categorias) c.id: c.grupo};

    final tramo = (await loadMesesContables()).tramoDe(mes);
    final txSnap = await household
        .collection('transactions')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(tramo.desde))
        .where('fecha', isLessThan: Timestamp.fromDate(tramo.hasta))
        .get();
    final gastoDocs = txSnap.docs.where((d) => d.data()['tipo'] == 'gasto').toList();
    final itemsSnaps = await Future.wait(gastoDocs.map((d) => d.reference.collection('items').get()));

    final lineas = <GroupLine>[];
    for (var i = 0; i < gastoDocs.length; i++) {
      final tx = TransactionSummary.fromFirestore(gastoDocs[i].id, gastoDocs[i].data());
      for (final itemDoc in itemsSnaps[i].docs) {
        final data = itemDoc.data();
        final grupoLinea = grupoPorCategoriaId[data['categoriaId'] as String?] ?? 'Sin categoría';
        if (grupoLinea != grupo) continue;
        lineas.add((
          textoOriginal: data['textoOriginal'] as String? ?? '',
          producto: data['productoNormalizado'] as String?,
          categoriaId: data['categoriaId'] as String?,
          precio: (data['precioTotal'] as num?)?.toDouble() ?? 0,
          pesoGramos: (data['pesoGramos'] as num?)?.toDouble(),
          fecha: tx.fecha,
          comercio: tx.comercio,
          pagadoPor: tx.pagadoPor,
          compartido: tx.compartido,
        ));
      }
    }
    lineas.sort((a, b) => b.fecha.compareTo(a.fecha));
    return lineas;
  }

  /// La ficha del producto [categoriaId]: lo gastado en él en los [months]
  /// meses que acaban en [mes], a qué precio y en qué compras.
  ///
  /// Hay que bajar las líneas de todos los tickets de la ventana, porque hasta
  /// que no se leen no se sabe cuáles traían el producto. Se piden todas a la
  /// vez, no una detrás de otra. Si algún día pesa, el siguiente paso es una
  /// consulta de grupo de colecciones sobre `items` filtrando por
  /// `categoriaId`, que a cambio pide un índice y una regla propios.
  Future<ProductSummary> loadProductSummary(String categoriaId, String mes, {int months = 6}) async {
    final household = await householdRef;
    final contables = await loadMesesContables();
    final fechaMes = primerDiaDe(mes);
    final meses = List.generate(
      months,
      (i) => mesDe(DateTime(fechaMes.year, fechaMes.month - (months - 1 - i))),
    );

    Category? categoria;
    for (final c in await loadCategories()) {
      if (c.id == categoriaId) {
        categoria = c;
        break;
      }
    }

    final txSnap = await household
        .collection('transactions')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(contables.inicioDe(meses.first)))
        .where('fecha', isLessThan: Timestamp.fromDate(contables.tramoDe(mes).hasta))
        .get();
    final gastoDocs = txSnap.docs.where((d) => d.data()['tipo'] == 'gasto').toList();
    final itemsSnaps = await Future.wait(gastoDocs.map((d) => d.reference.collection('items').get()));

    final compras = <ProductPurchase>[];
    String? nombreGuardado;
    for (var i = 0; i < gastoDocs.length; i++) {
      final tx = TransactionSummary.fromFirestore(gastoDocs[i].id, gastoDocs[i].data());
      for (final itemDoc in itemsSnaps[i].docs) {
        final data = itemDoc.data();
        if (data['categoriaId'] != categoriaId) continue;
        // Si la categoría se ha borrado, su nombre sigue en las líneas que ya
        // se guardaron: es el único sitio donde queda.
        nombreGuardado ??= data['productoNormalizado'] as String?;
        compras.add((
          precio: (data['precioTotal'] as num?)?.toDouble() ?? 0,
          pesoGramos: (data['pesoGramos'] as num?)?.toDouble(),
          precioPorKilo: (data['precioPorKilo'] as num?)?.toDouble(),
          fecha: tx.fecha,
          comercio: tx.comercio,
          pagadoPor: tx.pagadoPor,
          compartido: tx.compartido,
          mesContable: contables.mesContableDe(tx.fecha),
        ));
      }
    }

    return resumenDeProducto(
      producto: categoria?.nombre ?? nombreGuardado ?? 'Sin categoría',
      grupo: categoria?.grupo,
      meses: meses,
      compras: compras,
    );
  }

  /// Cuánto ha subido el precio de lo que compráis, comparando la primera
  /// mitad de los [months] meses que acaban en [mes] contra la segunda.
  ///
  /// Cuesta lo mismo que abrir la ficha de un producto: hay que bajar las
  /// líneas de todos los tickets de la ventana igual, solo que aquí se
  /// aprovechan todas en vez de filtrar una. Por eso no va en la carga de la
  /// pantalla de inicio, sino cuando se pide.
  Future<BasketInflation> loadBasketInflation(String mes, {int months = 6}) async {
    final household = await householdRef;
    final contables = await loadMesesContables();
    final fechaMes = primerDiaDe(mes);
    final meses = List.generate(
      months,
      (i) => mesDe(DateTime(fechaMes.year, fechaMes.month - (months - 1 - i))),
    );
    // La ventana se parte por la mitad: los primeros meses son el "antes".
    final mitad = meses.length ~/ 2;
    final mesesAntes = meses.sublist(0, mitad);
    final mesesAhora = meses.sublist(mitad);

    final txSnap = await household
        .collection('transactions')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(contables.inicioDe(meses.first)))
        .where('fecha', isLessThan: Timestamp.fromDate(contables.tramoDe(mes).hasta))
        .get();
    final gastoDocs = txSnap.docs.where((d) => d.data()['tipo'] == 'gasto').toList();
    final itemsSnaps = await Future.wait(gastoDocs.map((d) => d.reference.collection('items').get()));

    final puntos = <ProductPricePoint>[];
    for (var i = 0; i < gastoDocs.length; i++) {
      final mesDoc = contables.mesContableDe((gastoDocs[i].data()['fecha'] as Timestamp).toDate());
      for (final itemDoc in itemsSnaps[i].docs) {
        final data = itemDoc.data();
        final gramos = (data['pesoGramos'] as num?)?.toDouble();
        final producto = data['productoNormalizado'] as String?;
        if (gramos == null || gramos <= 0 || producto == null) continue;
        puntos.add((
          producto: producto,
          mes: mesDoc,
          gastado: (data['precioTotal'] as num?)?.toDouble() ?? 0,
          gramos: gramos,
        ));
      }
    }

    return inflacionDeCesta(puntos: puntos, mesesAntes: mesesAntes, mesesAhora: mesesAhora);
  }

  /// Los gastos del mes [mes] ("AAAA-MM"), del más reciente al más antiguo.
  /// Quién pagó y si es compartido son datos del ticket entero, así que el
  /// resumen basta para poder filtrarlos por persona sin leer sus líneas.
  Future<List<TransactionSummary>> loadMonthExpenses(String mes) async {
    final household = await householdRef;
    final tramo = (await loadMesesContables()).tramoDe(mes);
    final snap = await household
        .collection('transactions')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(tramo.desde))
        .where('fecha', isLessThan: Timestamp.fromDate(tramo.hasta))
        .get();
    final gastos = snap.docs
        .map((d) => TransactionSummary.fromFirestore(d.id, d.data()))
        .where((tx) => tx.tipo == 'gasto')
        .toList();
    gastos.sort((a, b) => b.fecha.compareTo(a.fecha));
    return gastos;
  }
}
