import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/category.dart';
import '../models/ticket_line_item.dart';
import '../models/transaction_summary.dart';
import '../utils/text_normalizer.dart';

typedef TicketItemInput = ({String textoOriginal, double precioTotal, Category categoria, double? pesoGramos});

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
    final mes = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

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
    final mes = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';
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
    final mes = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

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
    final mes = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';
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

  /// Total de gastos o ingresos (según [tipo]) por mes, para los últimos
  /// [months] meses (incluyendo el actual), en orden cronológico. La clave de
  /// cada entrada es "AAAA-MM".
  Future<List<MapEntry<String, double>>> loadMonthlyTotals({required String tipo, int months = 6}) async {
    final household = await householdRef;
    final now = DateTime.now();
    final meses = List.generate(months, (i) {
      final d = DateTime(now.year, now.month - (months - 1 - i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });

    final snap = await household.collection('transactions').where('tipo', isEqualTo: tipo).get();
    final totals = {for (final m in meses) m: 0.0};
    for (final doc in snap.docs) {
      final mes = doc.data()['mes'] as String?;
      if (mes != null && totals.containsKey(mes)) {
        totals[mes] = totals[mes]! + (doc.data()['importeTotal'] as num).toDouble();
      }
    }
    return meses.map((m) => MapEntry(m, totals[m]!)).toList();
  }

  /// Gasto del mes [mes] ("AAAA-MM") agrupado por grupo de categoría, de
  /// mayor a menor. Lee las líneas de cada ticket de ese mes, así que el
  /// coste crece con el número de tickets del mes (asumible a escala
  /// doméstica).
  Future<List<MapEntry<String, double>>> loadCategoryBreakdown(String mes) async {
    final household = await householdRef;
    final categorias = await loadCategories();
    final grupoPorCategoriaId = {for (final c in categorias) c.id: c.grupo};

    final txSnap = await household.collection('transactions').where('mes', isEqualTo: mes).get();
    final gastoDocs = txSnap.docs.where((d) => d.data()['tipo'] == 'gasto');
    // Las líneas de cada ticket se leen en paralelo, no una a una, para que
    // el dashboard no tarde más cuanto más tickets tenga el mes.
    final itemsSnaps = await Future.wait(gastoDocs.map((d) => d.reference.collection('items').get()));

    final totals = <String, double>{};
    for (final itemsSnap in itemsSnaps) {
      for (final itemDoc in itemsSnap.docs) {
        final categoriaId = itemDoc.data()['categoriaId'] as String?;
        final precio = (itemDoc.data()['precioTotal'] as num?)?.toDouble() ?? 0;
        final grupo = grupoPorCategoriaId[categoriaId] ?? 'Sin categoría';
        totals[grupo] = (totals[grupo] ?? 0) + precio;
      }
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted) MapEntry(e.key, e.value)];
  }

  /// Gasto del mes [mes] ("AAAA-MM") agrupado por quién pagó, de mayor a
  /// menor. A diferencia de [loadCategoryBreakdown], "quién pagó" es un dato
  /// del ticket en sí (no de cada línea), así que no hace falta leer las
  /// líneas. Solo cuenta el gasto compartido: uno marcado como personal (p.ej.
  /// un capricho de uno de los dos que no se reparte) no debe distorsionar
  /// quién ha puesto más dinero para la casa.
  Future<List<MapEntry<String, double>>> loadPersonBreakdown(String mes) async {
    final household = await householdRef;
    final txSnap = await household.collection('transactions').where('mes', isEqualTo: mes).get();

    final totals = <String, double>{};
    for (final doc in txSnap.docs) {
      final data = doc.data();
      if (data['tipo'] != 'gasto') continue;
      if (data['compartido'] == false) continue;
      final persona = data['pagadoPor'] as String? ?? 'Sin especificar';
      final importe = (data['importeTotal'] as num).toDouble();
      totals[persona] = (totals[persona] ?? 0) + importe;
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted) MapEntry(e.key, e.value)];
  }

  /// Total de gasto de cada persona este mes contando TODO gasto (compartido
  /// y personal): a diferencia de [loadPersonBreakdown], que solo mide el
  /// reparto del gasto compartido, esto responde "cuánto gasta cada uno en
  /// total", incluyendo sus caprichos personales. Un gasto pagado por "Ambos"
  /// se reparte a partes iguales entre las dos personas.
  Future<List<MapEntry<String, double>>> loadPersonTotalSpending(String mes) async {
    final household = await householdRef;
    final txSnap = await household.collection('transactions').where('mes', isEqualTo: mes).get();

    final totals = {'Cano': 0.0, 'Cana': 0.0};
    for (final doc in txSnap.docs) {
      final data = doc.data();
      if (data['tipo'] != 'gasto') continue;
      final persona = data['pagadoPor'] as String?;
      final importe = (data['importeTotal'] as num).toDouble();
      if (persona == 'Ambos') {
        totals['Cano'] = totals['Cano']! + importe / 2;
        totals['Cana'] = totals['Cana']! + importe / 2;
      } else if (totals.containsKey(persona)) {
        totals[persona!] = totals[persona]! + importe;
      }
    }
    final sorted = totals.entries.toList()
      ..removeWhere((e) => e.value <= 0)
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted) MapEntry(e.key, e.value)];
  }

  /// Gasto por categoría del mes [mes] ("AAAA-MM") junto al del mes
  /// inmediatamente anterior, para poder mostrar la variación en %. Ordenado
  /// por gasto actual de mayor a menor; solo incluye categorías con gasto
  /// este mes o el anterior.
  Future<List<({String grupo, double actual, double anterior})>> loadCategoryComparison(String mes) async {
    final partes = mes.split('-');
    final fechaMes = DateTime(int.parse(partes[0]), int.parse(partes[1]));
    final mesAnterior = DateTime(fechaMes.year, fechaMes.month - 1);
    final mesAnteriorStr = '${mesAnterior.year}-${mesAnterior.month.toString().padLeft(2, '0')}';

    final resultados = await Future.wait([
      loadCategoryBreakdown(mes),
      loadCategoryBreakdown(mesAnteriorStr),
    ]);
    final actual = resultados[0];
    final anteriorPorGrupo = {for (final e in resultados[1]) e.key: e.value};

    final grupos = {...actual.map((e) => e.key), ...anteriorPorGrupo.keys};
    final comparacion = [
      for (final grupo in grupos)
        (
          grupo: grupo,
          actual: actual.firstWhere((e) => e.key == grupo, orElse: () => MapEntry(grupo, 0.0)).value,
          anterior: anteriorPorGrupo[grupo] ?? 0.0,
        ),
    ];
    comparacion.sort((a, b) => b.actual.compareTo(a.actual));
    return comparacion;
  }
}
