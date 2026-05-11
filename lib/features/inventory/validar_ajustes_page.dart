import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ValidarAjustesPage extends StatefulWidget {
  const ValidarAjustesPage({super.key});

  @override
  State<ValidarAjustesPage> createState() => _ValidarAjustesPageState();
}

class _ValidarAjustesPageState extends State<ValidarAjustesPage> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _ajustes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAjustes();
  }

  Future<void> _fetchAjustes() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('ajustes_inventario')
          .select('''
            id,
            inventario_id,
            usuario_id,
            cantidad_reportada,
            creado_en,
            inventario (
              stock,
              tiendas (nombre),
              productos (descripcion_1, sku)
            )
          ''')
          .eq('estado', 'pendiente')
          .order('creado_en', ascending: false);

      // Fetch profile names manually to avoid FK join errors
      List<dynamic> ajustesConNombres = [];
      for (var a in data) {
        final userId = a['usuario_id'];
        String nombreUsuario = 'Usuario Desconocido';
        if (userId != null) {
          try {
            final perfil = await _supabase
                .from('perfiles')
                .select('nombre')
                .eq('id', userId)
                .maybeSingle();
            if (perfil != null && perfil['nombre'] != null) {
              nombreUsuario = perfil['nombre'];
            }
          } catch (_) {}
        }
        
        final mutAjuste = Map<String, dynamic>.from(a);
        mutAjuste['nombre_cajero'] = nombreUsuario;
        ajustesConNombres.add(mutAjuste);
      }

      if (mounted) {
        setState(() {
          _ajustes = ajustesConNombres;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching ajustes: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resolverAjuste(String ajusteId, String inventarioId, int nuevoStock, bool aprobar) async {
    try {
      if (aprobar) {
        // 1. Actualizar el inventario real
        await _supabase.from('inventario').update({
          'stock': nuevoStock,
          'actualizado_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', inventarioId);

        // 2. Marcar como aprobado
        await _supabase.from('ajustes_inventario').update({
          'estado': 'aprobado'
        }).eq('id', ajusteId);
      } else {
        // Marcar como rechazado
        await _supabase.from('ajustes_inventario').update({
          'estado': 'rechazado'
        }).eq('id', ajusteId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(aprobar ? "Ajuste Aprobado. Stock actualizado." : "Ajuste Rechazado."),
          backgroundColor: aprobar ? Colors.green : Colors.redAccent,
        ));
        _fetchAjustes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.orange));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Validar Ajustes"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ajustes.isEmpty
              ? const Center(
                  child: Text("No hay solicitudes pendientes.", style: TextStyle(color: Colors.white54, fontSize: 16)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _ajustes.length,
                  itemBuilder: (context, index) {
                    final a = _ajustes[index];
                    final String idAjuste = a['id'].toString();
                    final String idInv = a['inventario_id'].toString();
                    final String fecha = DateFormat('dd MMM, HH:mm').format(DateTime.parse(a['creado_en']).toLocal());
                    
                    final String nombreCajero = a['nombre_cajero'] ?? 'Usuario Desconocido';
                    final inv = a['inventario'];
                    final String tienda = inv?['tiendas']?['nombre'] ?? 'Sin tienda';
                    final String producto = inv?['productos']?['descripcion_1'] ?? 'Sin producto';
                    final String sku = inv?['productos']?['sku'] ?? '';
                    final int stockActual = inv?['stock'] ?? 0;
                    final int cantidadReportada = a['cantidad_reportada'] ?? 0;

                    return Card(
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Cajero: $nombreCajero", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                Text(fecha, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              ],
                            ),
                            const Divider(color: Colors.white10, height: 20),
                            Text("$producto (SKU: $sku)", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text("Tienda: $tienda", style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 15),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      const Text("Sistema", style: TextStyle(color: Colors.white54, fontSize: 12)),
                                      Text("$stockActual", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const Icon(Icons.arrow_forward, color: Colors.white38),
                                  Column(
                                    children: [
                                      const Text("Reportado", style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                                      Text("$cantidadReportada", style: const TextStyle(color: Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _resolverAjuste(idAjuste, idInv, cantidadReportada, false),
                                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                                    child: const Text("RECHAZAR", style: TextStyle(color: Colors.redAccent)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _resolverAjuste(idAjuste, idInv, cantidadReportada, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                    child: const Text("APROBAR", style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
