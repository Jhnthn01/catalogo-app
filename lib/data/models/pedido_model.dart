class PedidoModel {
  final dynamic id;
  final String? numeroPedido;
  final int? tiendaId;
  final String? clienteNombre;
  final String? clienteTelefono;
  final String? clienteDireccion;
  final String? tipoDocumento;
  final String? numeroDocumento;
  final String? tipoComprobante;
  final String? formaPago;
  final String? estado;
  final double total;
  final DateTime? fechaEntrega;
  final DateTime? createdAt;
  final List<dynamic>? detalles;

  PedidoModel({
    required this.id,
    this.numeroPedido,
    this.tiendaId,
    this.clienteNombre,
    this.clienteTelefono,
    this.clienteDireccion,
    this.tipoDocumento,
    this.numeroDocumento,
    this.tipoComprobante,
    this.formaPago,
    this.estado,
    this.total = 0.0,
    this.fechaEntrega,
    this.createdAt,
    this.detalles,
  });

  factory PedidoModel.fromJson(Map<String, dynamic> json) {
    return PedidoModel(
      id: json['id'],
      numeroPedido: json['numero_pedido']?.toString(),
      tiendaId: json['tienda_id'] != null ? int.tryParse(json['tienda_id'].toString()) : null,
      clienteNombre: json['cliente_nombre']?.toString(),
      clienteTelefono: json['cliente_telefono']?.toString(),
      clienteDireccion: json['cliente_direccion']?.toString(),
      tipoDocumento: json['tipo_documento']?.toString(),
      numeroDocumento: json['numero_documento']?.toString(),
      tipoComprobante: json['tipo_comprobante']?.toString(),
      formaPago: json['forma_pago']?.toString(),
      estado: json['estado']?.toString(),
      total: num.tryParse(json['total']?.toString() ?? '0')?.toDouble() ?? 0.0,
      fechaEntrega: json['fecha_entrega'] != null ? DateTime.tryParse(json['fecha_entrega'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      detalles: json['detalles_pedido'] != null ? List<dynamic>.from(json['detalles_pedido']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'numero_pedido': numeroPedido,
      'tienda_id': tiendaId,
      'cliente_nombre': clienteNombre,
      'cliente_telefono': clienteTelefono,
      'cliente_direccion': clienteDireccion,
      'tipo_documento': tipoDocumento,
      'numero_documento': numeroDocumento,
      'tipo_comprobante': tipoComprobante,
      'forma_pago': formaPago,
      'estado': estado,
      'total': total,
      if (fechaEntrega != null) 'fecha_entrega': fechaEntrega!.toIso8601String(),
    };
  }
}
