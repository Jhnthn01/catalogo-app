import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/data/models/producto_model.dart';

class ProductoService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// String con TODOS los campos de la tabla public.productos
  static const String selectFieldsComplete =
      'id, sku, upc, alu, marca, categoria, clase, sub_clase, estilo, descripcion_1, descripcion_2, color, costo, precio_venta, ultimo_costo, costo_medio';

  /// Obtiene lista de productos mapeados con datos completos
  Future<List<ProductoModel>> fetchProductos({
    int offset = 0,
    int limit = 100,
    String? searchQuery,
    String? categoria,
    String? clase,
    String? subClase,
    int? tiendaId,
  }) async {
    final fieldsWithInventario = tiendaId != null
        ? '$selectFieldsComplete, inventario!inner(stock, tienda_id)'
        : '$selectFieldsComplete, inventario(stock, tienda_id)';

    var query = _supabase.from('productos').select(fieldsWithInventario);

    if (tiendaId != null) {
      query = query.eq('inventario.tienda_id', tiendaId);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim();
      query = query.or(
        'descripcion_1.ilike.%$q%,sku.ilike.%$q%,upc.ilike.%$q%,alu.ilike.%$q%,marca.ilike.%$q%',
      );
    }

    if (categoria != null) query = query.eq('categoria', categoria);
    if (clase != null) query = query.eq('clase', clase);
    if (subClase != null) query = query.eq('sub_clase', subClase);

    final List<dynamic> data = await query
        .order('descripcion_1')
        .range(offset, offset + limit - 1);

    return data.map((json) => ProductoModel.fromJson(Map<String, dynamic>.from(json))).toList();
  }

  /// Obtiene un producto por ID con todos sus campos
  Future<ProductoModel?> getProductoById(dynamic id) async {
    final data = await _supabase
        .from('productos')
        .select('$selectFieldsComplete, inventario(stock, tienda_id)')
        .eq('id', id)
        .maybeSingle();

    if (data == null) return null;
    return ProductoModel.fromJson(Map<String, dynamic>.from(data));
  }

  /// Inserta un nuevo producto asegurando todos los campos
  Future<Map<String, dynamic>> crearProducto(ProductoModel producto) async {
    final res = await _supabase.from('productos').insert(producto.toJson()).select().single();
    return Map<String, dynamic>.from(res);
  }

  /// Actualiza un producto existente
  Future<void> actualizarProducto(dynamic id, Map<String, dynamic> datos) async {
    await _supabase.from('productos').update(datos).eq('id', id);
  }
}
