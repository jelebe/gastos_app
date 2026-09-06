class Category {
  Category({
    required this.id,
    required this.grupo,
    required this.nombre,
    required this.tipo,
    required this.trackWeight,
    required this.unidadDefault,
  });

  factory Category.fromFirestore(String id, Map<String, dynamic> data) {
    return Category(
      id: id,
      grupo: data['grupo'] as String,
      nombre: data['nombre'] as String,
      tipo: data['tipo'] as String,
      trackWeight: data['trackWeight'] as bool? ?? false,
      unidadDefault: data['unidadDefault'] as String? ?? 'unidad',
    );
  }

  final String id;
  final String grupo;
  final String nombre;
  final String tipo;
  final bool trackWeight;
  final String unidadDefault;
}
