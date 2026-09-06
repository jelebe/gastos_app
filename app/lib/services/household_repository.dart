import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/category.dart';
import '../models/dashboard_summary.dart';
import '../models/ticket_line_item.dart';
import '../models/transaction_summary.dart';
import '../utils/text_normalizer.dart';

typedef TicketItemInput = ({String textoOriginal, double precioTotal, Category categoria, double? pesoGramos});

/// Una línea de ticket ya guardada junto a los datos del ticket del que salió,
/// para poder listar "todo lo gastado en este grupo" sin perder de vista de
/// qué compra venía cada cosa.
typedef GroupLine = ({
  String textoOriginal,
  String? producto,
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

/// La clave de mes ("AAAA-MM") a la que pertenece [fecha]. Es como se guarda
/// el mes en cada transacción, para poder filtrar por él sin rangos de fecha.
String mesDe(DateTime fecha) => '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

/// El primer día del mes que nombra una clave "AAAA-MM".
DateTime primerDiaDe(String mes) {
  final partes = mes.split('-');
  return DateTime(int.parse(partes[0]), int.parse(partes[1]));
}

List<MapEntry<String, double>> _ordenadoPorImporte(Map<String, double> totales, {bool quitarVacios = false}) {
  final entradas = totales.entries.toList();
  if (quitarVacios) entradas.removeWhere((e) => e.value <= 0);
  entradas.sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in entradas) MapEntry(e.key, e.value)];
}

class AliasMatch {
  AliasMatch({required this.categoria, required this.aliasRef});

  final Category categoria;
  final DocumentReference<Map<String, dynamic>> aliasRef;
}

/// Punto de acceso único al hogar del usuario actual: su documento, sus
/// categorías y su diccionario de alias de producto (`productAliases`).
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

  Future<CollectionReference<Map<String, dynamic>>> get _categoriesCol async =>
      (await householdRef).collection('categories');

  Future<CollectionReference<Map<String, dynamic>>> get _aliasesCol async =>
      (await householdRef).collection('productAliases');

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

  /// Busca si esta línea de ticket ya se ha visto antes en el diccionario de
  /// alias. Devuelve la categoría asociada si hay coincidencia exacta.
  Future<AliasMatch?> matchLine(String rawText, List<Category> categories) async {
    final normalized = normalizeLine(rawText);
    if (normalized.isEmpty) return null;

    final col = await _aliasesCol;
    final snapshot =
        await col.where('textosOriginales', arrayContains: normalized).limit(1).get();
    if (snapshot.docs.isEmpty) return null;

    final alias = snapshot.docs.first;
    final categoriaId = alias.data()['categoriaId'] as String;
    Category? categoria;
    for (final c in categories) {
      if (c.id == categoriaId) {
        categoria = c;
        break;
      }
    }
    if (categoria == null) return null;

    return AliasMatch(categoria: categoria, aliasRef: alias.reference);
  }

  /// Registra (o completa) el alias para que la próxima vez que aparezca este
  /// mismo texto de ticket se resuelva sola contra [categoria].
  Future<void> learnAlias({required String rawText, required Category categoria}) async {
    final normalized = normalizeLine(rawText);
    if (normalized.isEmpty) return;

    final col = await _aliasesCol;
    final existing =
        await col.where('categoriaId', isEqualTo: categoria.id).limit(1).get();

    if (existing.docs.isEmpty) {
      await col.add({
        'textosOriginales': [normalized],
        'categoriaId': categoria.id,
        'productoNormalizado': categoria.nombre,
        'vecesUsado': 1,
      });
      return;
    }

    final doc = existing.docs.first;
    final knownTexts = List<String>.from(doc.data()['textosOriginales'] as List? ?? []);
    if (knownTexts.contains(normalized)) {
      await doc.reference.update({'vecesUsado': FieldValue.increment(1)});
    } else {
      await doc.reference.update({
        'textosOriginales': FieldValue.arrayUnion([normalized]),
        'vecesUsado': FieldValue.increment(1),
      });
    }
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
  /// una referencia viva. Los alias que apuntaban a esta categoría dejan de
  /// resolverse (matchLine los ignora si la categoría ya no existe).
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
  }

  /// Gastos o ingresos ya guardados (según [tipo]), del más reciente al más
  /// antiguo. Se ordena en el cliente para no depender de un índice
  /// compuesto en Firestore.
  Stream<List<TransactionSummary>> watchTransactions(String tipo) {
    return Stream.fromFuture(householdRef).asyncExpand(
      (ref) => ref.collection('transactions').where('tipo', isEqualTo: tipo).snapshots().map((snap) {
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

  /// Todo lo que enseña la pantalla de inicio del mes [mes] ("AAAA-MM"), con
  /// la tendencia de los [months] meses que acaban en él.
  ///
  /// Sale de una única consulta por esa ventana de meses: dentro de ella están
  /// tanto el mes elegido (para los desgloses) como el anterior (para la
  /// comparación), así que no hace falta volver a Firestore una vez por
  /// bloque. Solo se bajan las líneas de los tickets de esos dos meses, que
  /// son los únicos que se desglosan por categoría; del resto de la ventana
  /// basta el importe total de cada ticket.
  Future<DashboardSummary> loadDashboardSummary(String mes, {int months = 6}) async {
    final household = await householdRef;
    final fechaMes = primerDiaDe(mes);
    final mesAnterior = mesDe(DateTime(fechaMes.year, fechaMes.month - 1));
    final meses = List.generate(
      months,
      (i) => mesDe(DateTime(fechaMes.year, fechaMes.month - (months - 1 - i))),
    );
    // Con months = 1 el mes anterior se queda fuera de la serie, pero la
    // comparación lo sigue necesitando.
    final ventana = {...meses, mesAnterior}.toList();

    final categorias = await loadCategories();
    final grupoPorCategoriaId = {for (final c in categorias) c.id: c.grupo};

    final txSnap = await household.collection('transactions').where('mes', whereIn: ventana).get();

    // Los tickets cuyas líneas hacen falta: los del mes que se mira y los del
    // anterior. Se leen todos a la vez, no uno detrás de otro.
    final docsConLineas = txSnap.docs.where((d) {
      final data = d.data();
      return data['tipo'] == 'gasto' && (data['mes'] == mes || data['mes'] == mesAnterior);
    }).toList();
    final itemsSnaps = await Future.wait(docsConLineas.map((d) => d.reference.collection('items').get()));

    final gastosPorMes = {for (final m in meses) m: 0.0};
    final ingresosPorMes = {for (final m in meses) m: 0.0};
    final porPersona = <String, double>{};
    final totalPorPersona = {'Cano': 0.0, 'Cana': 0.0};

    for (final doc in txSnap.docs) {
      final data = doc.data();
      final mesDoc = data['mes'] as String?;
      final importe = (data['importeTotal'] as num).toDouble();
      final esGasto = data['tipo'] == 'gasto';

      if (mesDoc != null) {
        final serie = esGasto ? gastosPorMes : ingresosPorMes;
        if (serie.containsKey(mesDoc)) serie[mesDoc] = serie[mesDoc]! + importe;
      }
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
      final esDelMes = docsConLineas[i].data()['mes'] == mes;
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
      gastosPorMes: [for (final m in meses) MapEntry(m, gastosPorMes[m]!)],
      ingresosPorMes: [for (final m in meses) MapEntry(m, ingresosPorMes[m]!)],
      categoryBreakdown: _ordenadoPorImporte(gastoPorGrupo),
      categoryComparison: comparacion,
      personBreakdown: _ordenadoPorImporte(porPersona),
      personTotalSpending: _ordenadoPorImporte(totalPorPersona, quitarVacios: true),
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

    final txSnap = await household.collection('transactions').where('mes', isEqualTo: mes).get();
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

  /// Los gastos del mes [mes] ("AAAA-MM"), del más reciente al más antiguo.
  /// Quién pagó y si es compartido son datos del ticket entero, así que el
  /// resumen basta para poder filtrarlos por persona sin leer sus líneas.
  Future<List<TransactionSummary>> loadMonthExpenses(String mes) async {
    final household = await householdRef;
    final snap = await household.collection('transactions').where('mes', isEqualTo: mes).get();
    final gastos = snap.docs
        .map((d) => TransactionSummary.fromFirestore(d.id, d.data()))
        .where((tx) => tx.tipo == 'gasto')
        .toList();
    gastos.sort((a, b) => b.fecha.compareTo(a.fecha));
    return gastos;
  }
}
