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

  // Flag: true cuando el admin eligió la tienda manualmente.
  // Evita que cargarTiendas() sobreescriba la selección al regresar de otra vista.
  bool _seleccionManual = false;

  bool get sinTiendaAsignada {
    final rol = usuarioRol?.toLowerCase() ?? 'cliente';
    final esAdminOGerente = (rol == 'admin' || rol == 'administrador' || rol == 'gerente');
    return !esAdminOGerente && usuarioTiendaId == null && usuarioRol != null;
  }

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
            // Si el admin ya eligió una tienda manualmente, respetarla.
            if (_seleccionManual && tiendaActivaId.value != null) {
              // No sobreescribir — conservar la elección previa.
            } else if (usuarioTiendaId != null) {
              tiendaActivaId.value = usuarioTiendaId;
            } else {
              if (tiendas.isNotEmpty) {
                final sedeCentral = tiendas.firstWhere((t) => t['id'] == 1, orElse: () => tiendas.first);
                tiendaActivaId.value = sedeCentral['id'] as int;
              }
            }
          } else {
            // Rol operativo: siempre fijado a su tienda, sin excepción.
            tiendaActivaId.value = usuarioTiendaId;
            _seleccionManual = false;
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
        _seleccionManual = false;
      }
    } catch (e) {
      debugPrint('Error cargando tiendas: $e');
    }
  }

  void seleccionarTienda(int id) {
    // Si el rol es operativo, no permitir cambiar la tienda (seguridad frontal).
    final rol = usuarioRol?.toLowerCase() ?? 'cliente';
    if (rol == 'admin' || rol == 'administrador' || rol == 'gerente') {
      _seleccionManual = true;
      tiendaActivaId.value = id;
    }
  }

  /// Llama esto en el logout para limpiar el estado de sesión.
  void limpiarSesion() {
    _seleccionManual = false;
    tiendaActivaId.value = null;
    usuarioRol = null;
    usuarioTiendaId = null;
    tiendas = [];
  }
}
