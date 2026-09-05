import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/category.dart';
import '../utils/text_normalizer.dart';

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

  Future<void> saveTicket({
    required List<({String textoOriginal, double precioTotal, Category categoria, double? pesoGramos})> items,
    required double importeTotal,
    String? comercio,
    required DateTime fecha,
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
      'moneda': 'EUR',
      'creadoPor': uid,
    });

    final batch = FirebaseFirestore.instance.batch();
    final itemsCol = transactionRef.collection('items');
    for (final item in items) {
      final precioPorKilo = (item.categoria.trackWeight && item.pesoGramos != null && item.pesoGramos! > 0)
          ? item.precioTotal / (item.pesoGramos! / 1000)
          : null;
      batch.set(itemsCol.doc(), {
        'textoOriginal': item.textoOriginal,
        'categoriaId': item.categoria.id,
        'productoNormalizado': item.categoria.nombre,
        'precioTotal': item.precioTotal,
        'pesoGramos': item.pesoGramos,
        'precioPorKilo': precioPorKilo,
      });
    }
    await batch.commit();
  }
}
