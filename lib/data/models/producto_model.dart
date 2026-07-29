class ProductoModel {
  final dynamic id;
  final String? sku;
  final String? upc;
  final String? alu;
  final String? marca;
  final String? categoria;
  final String? clase;
  final String? subClase;
  final String? estilo;
  final String? descripcion1;
  final String? descripcion2;
  final String? color;
  final double costo;
  final double precioVenta;
  final double ultimoCosto;
  final double costoMedio;
  final double? stock;

  ProductoModel({
    required this.id,
    this.sku,
    this.upc,
    this.alu,
    this.marca,
    this.categoria,
    this.clase,
    this.subClase,
    this.estilo,
    this.descripcion1,
    this.descripcion2,
    this.color,
    this.costo = 0.0,
    this.precioVenta = 0.0,
    this.ultimoCosto = 0.0,
    this.costoMedio = 0.0,
    this.stock,
  });

  /// Getter con fallback para el Último Costo: si es 0 o nulo, usa 'costo'
  double get effectiveUltimoCosto {
    return (ultimoCosto > 0) ? ultimoCosto : costo;
  }

  /// Getter con fallback para el Costo Medio (PMP): si es 0 o nulo, usa 'costo'
  double get effectiveCostoMedio {
    return (costoMedio > 0) ? costoMedio : costo;
  }

  factory ProductoModel.fromJson(Map<String, dynamic> json) {
    // Manejo seguro del stock si viene anidado desde la relación 'inventario'
    double? parsedStock;
    if (json['inventario'] != null) {
      if (json['inventario'] is List && (json['inventario'] as List).isNotEmpty) {
        final invList = json['inventario'] as List;
        parsedStock = invList.fold<double>(
          0.0,
          (sum, item) => sum + (num.tryParse(item['stock']?.toString() ?? '0')?.toDouble() ?? 0.0),
        );
      } else if (json['inventario'] is Map) {
        parsedStock = num.tryParse(json['inventario']['stock']?.toString() ?? '0')?.toDouble();
      }
    } else if (json['stock'] != null) {
      parsedStock = num.tryParse(json['stock'].toString())?.toDouble();
    }

    return ProductoModel(
      id: json['id'],
      sku: json['sku']?.toString(),
      upc: json['upc']?.toString(),
      alu: json['alu']?.toString(),
      marca: json['marca']?.toString(),
      categoria: json['categoria']?.toString(),
      clase: json['clase']?.toString(),
      subClase: json['sub_clase']?.toString(),
      estilo: json['estilo']?.toString(),
      descripcion1: json['descripcion_1']?.toString(),
      descripcion2: json['descripcion_2']?.toString(),
      color: json['color']?.toString(),
      costo: num.tryParse(json['costo']?.toString() ?? '0')?.toDouble() ?? 0.0,
      precioVenta: num.tryParse(json['precio_venta']?.toString() ?? '0')?.toDouble() ?? 0.0,
      ultimoCosto: num.tryParse(json['ultimo_costo']?.toString() ?? '0')?.toDouble() ?? 0.0,
      costoMedio: num.tryParse(json['costo_medio']?.toString() ?? '0')?.toDouble() ?? 0.0,
      stock: parsedStock,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'sku': sku,
      'upc': upc,
      'alu': alu,
      'marca': marca,
      'categoria': categoria,
      'clase': clase,
      'sub_clase': subClase,
      'estilo': estilo,
      'descripcion_1': descripcion1,
      'descripcion_2': descripcion2,
      'color': color,
      'costo': costo,
      'precio_venta': precioVenta,
      'ultimo_costo': ultimoCosto,
      'costo_medio': costoMedio,
    };
  }
}
