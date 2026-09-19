class KardexMovimiento {
  final dynamic id;
  final dynamic productoId;
  final int? tiendaId;
  final String tipoMovimiento;
  final String? origenTipo;
  final String? origenId;
  final double cantidad;
  final double? costoUnitario;
  final double? stockAnterior;
  final double? stockResultante;
  final double? costoMedioMomento;
  final String? usuarioId;
  final DateTime? createdAt;

  // Nuevos campos
  final String? lote;
  final String? unidadMedida;

  // Información extendida relacional
  final String? productoSku;
  final String? productoDescripcion;
  final String? tiendaNombre;
  final String? usuarioNombre;

  KardexMovimiento({
    this.id,
    required this.productoId,
    this.tiendaId,
    required this.tipoMovimiento,
    this.origenTipo,
    this.origenId,
    required this.cantidad,
    this.costoUnitario,
    this.stockAnterior,
    this.stockResultante,
    this.costoMedioMomento,
    this.usuarioId,
    this.createdAt,
    this.lote,
    this.unidadMedida,
    this.productoSku,
    this.productoDescripcion,
    this.tiendaNombre,
    this.usuarioNombre,
  });

  KardexMovimiento copyWith({
    dynamic id,
    dynamic productoId,
    int? tiendaId,
    String? tipoMovimiento,
    String? origenTipo,
    String? origenId,
    double? cantidad,
    double? costoUnitario,
    double? stockAnterior,
    double? stockResultante,
    double? costoMedioMomento,
    String? usuarioId,
    DateTime? createdAt,
    String? lote,
    String? unidadMedida,
    String? productoSku,
    String? productoDescripcion,
    String? tiendaNombre,
    String? usuarioNombre,
  }) {
    return KardexMovimiento(
      id: id ?? this.id,
      productoId: productoId ?? this.productoId,
      tiendaId: tiendaId ?? this.tiendaId,
      tipoMovimiento: tipoMovimiento ?? this.tipoMovimiento,
      origenTipo: origenTipo ?? this.origenTipo,
      origenId: origenId ?? this.origenId,
      cantidad: cantidad ?? this.cantidad,
      costoUnitario: costoUnitario ?? this.costoUnitario,
      stockAnterior: stockAnterior ?? this.stockAnterior,
      stockResultante: stockResultante ?? this.stockResultante,
      costoMedioMomento: costoMedioMomento ?? this.costoMedioMomento,
      usuarioId: usuarioId ?? this.usuarioId,
      createdAt: createdAt ?? this.createdAt,
      lote: lote ?? this.lote,
      unidadMedida: unidadMedida ?? this.unidadMedida,
      productoSku: productoSku ?? this.productoSku,
      productoDescripcion: productoDescripcion ?? this.productoDescripcion,
      tiendaNombre: tiendaNombre ?? this.tiendaNombre,
      usuarioNombre: usuarioNombre ?? this.usuarioNombre,
    );
  }

  // Getters para fácil acceso a datos extendidos
  String? get sku => productoSku;
  String? get descripcion_1 => productoDescripcion;
  String? get descripcion1 => productoDescripcion;
  String? get nombre => tiendaNombre;
  String? get nombreTienda => tiendaNombre;
  String? get nombreUsuario => usuarioNombre;

  /// Mapea tipoMovimiento a abreviatura para columna TIP. DOC.
  String get tipDocAbreviado {
    switch (tipoMovimiento.toUpperCase()) {
      case 'SALIDA':
        return 'VTA';
      case 'ENTRADA':
        return 'COM';
      case 'AJUSTE':
        return 'AJU';
      default:
        return tipoMovimiento.length > 3
            ? tipoMovimiento.substring(0, 3).toUpperCase()
            : tipoMovimiento.toUpperCase();
    }
  }

  factory KardexMovimiento.fromJson(Map<String, dynamic> json) {
    final prodMap = json['productos'] is Map<String, dynamic>
        ? json['productos'] as Map<String, dynamic>
        : null;
    final tiendaMap = json['tiendas'] is Map<String, dynamic>
        ? json['tiendas'] as Map<String, dynamic>
        : null;
    final perfilMap = json['perfiles'] is Map<String, dynamic>
        ? json['perfiles'] as Map<String, dynamic>
        : null;

    return KardexMovimiento(
      id: json['id'],
      productoId: json['producto_id'],
      tiendaId: json['tienda_id'] != null
          ? int.tryParse(json['tienda_id'].toString())
          : null,
      tipoMovimiento: json['tipo_movimiento']?.toString() ?? '',
      origenTipo: json['origen_tipo']?.toString(),
      origenId: json['origen_id']?.toString(),
      cantidad: num.tryParse(json['cantidad']?.toString() ?? '0')?.toDouble() ?? 0.0,
      costoUnitario: json['costo_unitario'] != null
          ? num.tryParse(json['costo_unitario'].toString())?.toDouble()
          : null,
      stockAnterior: json['stock_anterior'] != null
          ? num.tryParse(json['stock_anterior'].toString())?.toDouble()
          : null,
      stockResultante: json['stock_resultante'] != null
          ? num.tryParse(json['stock_resultante'].toString())?.toDouble()
          : null,
      costoMedioMomento: json['costo_medio_momento'] != null
          ? num.tryParse(json['costo_medio_momento'].toString())?.toDouble()
          : null,
      usuarioId: json['usuario_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      lote: json['lote']?.toString(),
      unidadMedida: json['unidad_medida']?.toString() ?? 'UND',
      productoSku: prodMap?['sku']?.toString(),
      productoDescripcion: prodMap?['descripcion_1']?.toString(),
      tiendaNombre: tiendaMap?['nombre']?.toString(),
      usuarioNombre: perfilMap?['nombre']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'producto_id': productoId,
      if (tiendaId != null) 'tienda_id': tiendaId,
      'tipo_movimiento': tipoMovimiento,
      if (origenTipo != null) 'origen_tipo': origenTipo,
      if (origenId != null) 'origen_id': origenId,
      'cantidad': cantidad,
      if (costoUnitario != null) 'costo_unitario': costoUnitario,
      if (stockAnterior != null) 'stock_anterior': stockAnterior,
      if (stockResultante != null) 'stock_resultante': stockResultante,
      if (costoMedioMomento != null) 'costo_medio_momento': costoMedioMomento,
      if (usuarioId != null) 'usuario_id': usuarioId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (lote != null) 'lote': lote,
      if (unidadMedida != null) 'unidad_medida': unidadMedida,
    };
  }
}
