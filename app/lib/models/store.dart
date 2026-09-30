/// El grupo en el que cae una tienda que no tiene ninguno puesto.
///
/// Es una etiqueta de pantalla, no un valor guardado: en Firestore esas
/// tiendas sencillamente no tienen `grupo`.
const sinGrupo = 'Sin grupo';

/// Un establecimiento donde se compra, de la lista del hogar.
///
/// Los tickets siguen guardando el nombre y no una referencia: así todo lo que
/// ya agrupa por comercio sigue funcionando, y quitar una tienda de la lista
/// no deja tickets huérfanos. La lista existe para que el nombre se escriba
/// una vez y no de cinco formas distintas.
class Store {
  Store({required this.id, required this.nombre, this.grupo});

  factory Store.fromFirestore(String id, Map<String, dynamic> data) {
    final grupo = (data['grupo'] as String?)?.trim();
    return Store(
      id: id,
      nombre: data['nombre'] as String? ?? '',
      grupo: (grupo == null || grupo.isEmpty) ? null : grupo,
    );
  }

  final String id;
  final String nombre;

  /// De qué tipo es el sitio: "Supermercados", "Bares", "Luz"... Sirve para
  /// tener juntos el genérico y los concretos ("Bar" junto a "Bar Paco"), que
  /// es lo que hace navegable una lista larga.
  final String? grupo;

  /// El grupo tal y como se enseña, con etiqueta para las que no tienen.
  String get grupoVisible => grupo ?? sinGrupo;
}

/// Reparte las tiendas por grupo, con los grupos por orden alfabético y
/// [sinGrupo] siempre al final, porque es el cajón de lo que aún no se ha
/// colocado.
List<MapEntry<String, List<Store>>> agrupaTiendas(List<Store> tiendas) {
  final porGrupo = <String, List<Store>>{};
  for (final tienda in tiendas) {
    porGrupo.putIfAbsent(tienda.grupoVisible, () => []).add(tienda);
  }
  final grupos = porGrupo.keys.toList()
    ..sort((a, b) {
      if (a == sinGrupo) return 1;
      if (b == sinGrupo) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  for (final lista in porGrupo.values) {
    lista.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }
  return [for (final g in grupos) MapEntry(g, porGrupo[g]!)];
}
