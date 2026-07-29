class InventarioModel {
  final dynamic id;
  final dynamic productoId;
  final int? tiendaId;
  final double stock;
  final String? ubicacion;
  final DateTime? updatedAt;

  InventarioModel({
    required this.id,
    required this.productoId,
    this.tiendaId,
    this.stock = 0.0,
    this.ubicacion,
    this.updatedAt,
  });

  factory InventarioModel.fromJson(Map<String, dynamic> json) {
    return InventarioModel(
      id: json['id'],
      productoId: json['producto_id'],
      tiendaId: json['tienda_id'] != null ? int.tryParse(json['tienda_id'].toString()) : null,
      stock: num.tryParse(json['stock']?.toString() ?? '0')?.toDouble() ?? 0.0,
      ubicacion: json['ubicacion']?.toString(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'producto_id': productoId,
      'tienda_id': tiendaId,
      'stock': stock,
      'ubicacion': ubicacion,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
