import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TiendaService {
  static final TiendaService _instance = TiendaService._internal();

  factory TiendaService() {
    return _instance;
  }

  TiendaService._internal();

  final ValueNotifier<int?> tiendaSeleccionadaId = ValueNotifier<int?>(null);
  List<Map<String, dynamic>> tiendas = [];

  Future<void> cargarTiendas() async {
    try {
      final response = await Supabase.instance.client
          .from('tiendas')
          .select('id, nombre, codigo_tienda')
          .order('id');
      
      tiendas = List<Map<String, dynamic>>.from(response);

      // Si no hay tienda seleccionada y hay tiendas disponibles, selecciona la primera.
      if (tiendaSeleccionadaId.value == null && tiendas.isNotEmpty) {
        tiendaSeleccionadaId.value = tiendas.first['id'] as int;
      }
    } catch (e) {
      debugPrint('Error cargando tiendas: $e');
    }
  }

  void seleccionarTienda(int id) {
    tiendaSeleccionadaId.value = id;
  }
}
