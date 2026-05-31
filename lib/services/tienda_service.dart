import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TiendaService {
  static final TiendaService _instance = TiendaService._internal();

  factory TiendaService() {
    return _instance;
  }

  TiendaService._internal();

  final ValueNotifier<int?> tiendaActivaId = ValueNotifier<int?>(null);
  ValueNotifier<int?> get tiendaSeleccionadaId => tiendaActivaId;
  
  List<Map<String, dynamic>> tiendas = [];
  String? usuarioRol;
  int? usuarioTiendaId;

  Future<void> cargarTiendas() async {
    try {
      final response = await Supabase.instance.client
          .from('tiendas')
          .select('id, nombre, codigo_tienda')
          .order('id');
      
      tiendas = List<Map<String, dynamic>>.from(response);

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profileResponse = await Supabase.instance.client
            .from('perfiles')
            .select('rol, tienda_id')
            .eq('id', user.id)
            .maybeSingle();
        
        if (profileResponse != null) {
          usuarioRol = profileResponse['rol'] as String? ?? 'cliente';
          usuarioTiendaId = profileResponse['tienda_id'] as int?;
          
          final rol = usuarioRol!.toLowerCase();
          if (rol == 'admin' || rol == 'administrador' || rol == 'gerente') {
            if (tiendaActivaId.value == null && tiendas.isNotEmpty) {
              tiendaActivaId.value = tiendas.first['id'] as int;
            }
          } else {
            // Rol operativo: inicializa estrictamente con el tienda_id de su registro
            tiendaActivaId.value = usuarioTiendaId;
          }
        } else {
          usuarioRol = 'cliente';
          usuarioTiendaId = null;
          if (tiendaActivaId.value == null && tiendas.isNotEmpty) {
            tiendaActivaId.value = tiendas.first['id'] as int;
          }
        }
      } else {
        usuarioRol = null;
        usuarioTiendaId = null;
        tiendaActivaId.value = null;
      }
    } catch (e) {
      debugPrint('Error cargando tiendas: $e');
    }
  }

  void seleccionarTienda(int id) {
    // Si el rol es operativo, no permitir cambiar la tienda (por seguridad frontal)
    final rol = usuarioRol?.toLowerCase() ?? 'cliente';
    if (rol == 'admin' || rol == 'administrador' || rol == 'gerente') {
      tiendaActivaId.value = id;
    }
  }
}
