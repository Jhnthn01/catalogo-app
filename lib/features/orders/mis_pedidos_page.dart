import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MisPedidosPage extends StatefulWidget {
  const MisPedidosPage({super.key});

  @override
  State<MisPedidosPage> createState() => _MisPedidosPageState();
}

class _MisPedidosPageState extends State<MisPedidosPage> {
  final _supabase = Supabase.instance.client;
  String? _userRol;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _fetchRolYPedidos();
  }

  Future<void> _fetchRolYPedidos() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    _userId = user.id;

    try {
      final perfilData = await _supabase
          .from('perfiles')
          .select('rol')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _userRol = perfilData?['rol'] as String? ?? 'cliente';
        });
      }
    } catch (e) {
      debugPrint("Error fetching rol: $e");
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPedidos() async {
    if (_userId == null) return [];

    try {
      var query = _supabase
          .from('pedidos')
          .select('''
          id,
          total,
          estado,
          created_at,
          creado_en,
          fecha_entrega,
          nombre_cliente,
          tipo_documento,
          numero_documento,
          telefono_cliente,
          tipo_comprobante,
          forma_pago,
          requiere_regularizacion,
          segundo_recoge,
          identidad_verificada,
          detalles_pedido (
            id,
            cantidad,
            precio_unitario,
            cantidad_despachada,
            productos (
              descripcion_1
            )
          )
        ''');

      if (_userRol != 'admin' && _userRol != 'despachador' && _userRol != 'gerente') {
        query = query.eq('usuario_id', _userId!);
      }

      final response = await query.order('creado_en', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("Error en Pedidos: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userRol == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(title: const Text("Pedidos de Clientes"), backgroundColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Pedidos de Clientes"),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchPedidos(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No hay pedidos",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final pedidos = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: pedidos.length,
            itemBuilder: (context, index) {
              return PedidoCardItem(
                pedido: pedidos[index],
                userRol: _userRol!,
                onRefresh: () => setState(() {}),
              );
            },
          );
        },
      ),
    );
  }
}

class PedidoCardItem extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final String userRol;
  final VoidCallback onRefresh;

  const PedidoCardItem({super.key, required this.pedido, required this.userRol, required this.onRefresh});

  @override
  State<PedidoCardItem> createState() => _PedidoCardItemState();
}

class _PedidoCardItemState extends State<PedidoCardItem> {
  late List<dynamic> _detalles;
  bool _isSaving = false;
  bool _haCambiado = false;
  bool _identidadVerificada = false;

  @override
  void initState() {
    super.initState();
    _detalles = List.from(widget.pedido['detalles_pedido'] ?? []);
    _identidadVerificada = widget.pedido['identidad_verificada'] == true;
  }

  void _actualizarCantidad(int index, int newQty) {
    if (newQty < 1) return;
    setState(() {
      _detalles[index]['cantidad'] = newQty;
      _haCambiado = true;
    });
  }

  void _actualizarCantidadDespachada(int index, int newQty) {
    if (newQty < 0) return;
    setState(() {
      _detalles[index]['cantidad_despachada'] = newQty;
    });
  }

  Future<void> _guardarCambiosPedido() async {
    setState(() => _isSaving = true);
    try {
      double nuevoTotal = 0;
      for (var d in _detalles) {
        nuevoTotal += (d['cantidad'] as int) * double.parse(d['precio_unitario'].toString());
        await Supabase.instance.client
            .from('detalles_pedido')
            .update({'cantidad': d['cantidad']})
            .eq('id', d['id']);
      }
      await Supabase.instance.client
          .from('pedidos')
          .update({'total': nuevoTotal})
          .eq('id', widget.pedido['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cantidades actualizadas", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        widget.onRefresh();
      }
    } catch (e) {
      debugPrint("Error guardando pedido: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _despacharPedido() async {
    setState(() => _isSaving = true);
    try {
      for (var d in _detalles) {
        await Supabase.instance.client
            .from('detalles_pedido')
            .update({'cantidad_despachada': d['cantidad_despachada'] ?? 0})
            .eq('id', d['id']);
      }
      await Supabase.instance.client
          .from('pedidos')
          .update({
            'estado': 'despachado',
            'identidad_verificada': _identidadVerificada
          })
          .eq('id', widget.pedido['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pedido despachado", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        widget.onRefresh();
      }
    } catch (e) {
      debugPrint("Error despachando pedido: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancelarPedido() async {
    try {
      await Supabase.instance.client
          .from('pedidos')
          .update({'estado': 'cancelado'})
          .eq('id', widget.pedido['id'].toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pedido cancelado correctamente")),
        );
        widget.onRefresh();
      }
    } catch (e) {
      debugPrint("Error al cancelar: $e");
    }
  }

  void _mostrarDialogoConfirmarCancelacion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("�Cancelar pedido?", style: TextStyle(color: Colors.white)),
        content: const Text("Esta acci�n notificar� a la tienda. �Deseas continuar?", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VOLVER", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelarPedido();
            },
            child: const Text("S�, CANCELAR", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoChip(String estado) {
    Color color;
    switch (estado.toLowerCase()) {
      case 'pendiente': color = Colors.orange; break;
      case 'completado': color = Colors.green; break;
      case 'despachado': color = Colors.blue; break;
      case 'cancelado': color = Colors.red; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(5)),
      child: Text(estado.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime fechaCreacion = DateTime.parse(widget.pedido['creado_en'] ?? widget.pedido['created_at']).toLocal();
    final DateTime? fechaEntrega = widget.pedido['fecha_entrega'] != null ? DateTime.parse(widget.pedido['fecha_entrega']).toLocal() : null;
    final estado = widget.pedido['estado'].toString().toLowerCase();
    
    // Calculate current UI total based on edited quantities
    double currentTotal = 0;
    for (var d in _detalles) {
      currentTotal += (d['cantidad'] as int) * double.parse(d['precio_unitario'].toString());
    }

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        iconColor: Colors.blue,
        collapsedIconColor: Colors.white54,
        title: Text("Pedido #${widget.pedido['id'].toString().substring(0, 8)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Creado: ${DateFormat('dd/MM/yyyy hh:mm a').format(fechaCreacion)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (fechaEntrega != null)
              Text("Entrega: ${DateFormat('dd/MM/yyyy hh:mm a').format(fechaEntrega)}", style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
            Text("Total: \$${currentTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
          ],
        ),
        trailing: _buildEstadoChip(estado),
        children: [
          if (widget.pedido['requiere_regularizacion'] == true)
            Container(
              width: double.infinity,
              color: Colors.redAccent.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text("⚠️ Este pedido forzó stock negativo. Requiere regularizar inventario.", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("DETALLES DEL CLIENTE", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("Nombre: ${widget.pedido['nombre_cliente'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text("Documento: ${widget.pedido['tipo_documento'] ?? ''} ${widget.pedido['numero_documento'] ?? ''}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text("Teléfono: ${widget.pedido['telefono_cliente'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                if (widget.pedido['segundo_recoge'] != null) ...[
                  const SizedBox(height: 8),
                  const Text("SEGUNDO AUTORIZADO", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("${widget.pedido['segundo_recoge']}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                ],
                const SizedBox(height: 12),
                const Text("LOGÍSTICA", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("Entrega: ${fechaEntrega != null ? DateFormat('dd/MM/yyyy hh:mm a').format(fechaEntrega) : 'No especificada'}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text("Verificación: ${widget.pedido['identidad_verificada'] == true ? 'Verificado' : 'Pendiente'}", style: TextStyle(color: widget.pedido['identidad_verificada'] == true ? Colors.green : Colors.orangeAccent, fontSize: 13)),
                const SizedBox(height: 12),
                const Text("FINANZAS", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("Comprobante: ${widget.pedido['tipo_comprobante'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 4),
                Text("Forma de pago:\n${(widget.pedido['forma_pago'] ?? '').toString().replaceAll(' | ', '\n')}", style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 8),
                Text("TOTAL: \$${currentTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          ..._detalles.asMap().entries.map((entry) {
            final int index = entry.key;
            final detalle = entry.value;
            final int qtyOriginal = detalle['cantidad'];
            final int qtyDespachada = detalle['cantidad_despachada'] ?? 0;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detalle['productos']?['descripcion_1'] ?? 'Producto Desconocido', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if ((widget.userRol == 'vendedor' || widget.userRol == 'cajero' || widget.userRol == 'admin') && estado == 'pendiente')
                        Row(
                          children: [
                            const Text("Pedido: ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                              onPressed: () => _actualizarCantidad(index, qtyOriginal - 1),
                            ),
                            Text("$qtyOriginal", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
                              onPressed: () => _actualizarCantidad(index, qtyOriginal + 1),
                            ),
                          ],
                        )
                      else
                        Text("Pedido: $qtyOriginal", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        
                      if (widget.userRol == 'despachador' && estado == 'pendiente')
                        Row(
                          children: [
                            const Text("Despachar: ", style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                            IconButton(
                              icon: const Icon(Icons.remove, color: Colors.white54, size: 18),
                              onPressed: () => _actualizarCantidadDespachada(index, qtyDespachada - 1),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                              child: Text("$qtyDespachada", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: Colors.white54, size: 18),
                              onPressed: () => _actualizarCantidadDespachada(index, qtyDespachada + 1),
                            ),
                          ],
                        )
                      else
                        Text("Despachado: $qtyDespachada", style: const TextStyle(color: Colors.blueAccent, fontSize: 13)),
                    ],
                  )
                ],
              ),
            );
          }),
          
          if (widget.userRol == 'despachador' && estado == 'pendiente')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Verificaci�n de Identidad", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Titular: ${widget.pedido['nombre_cliente'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    if (widget.pedido['segundo_recoge'] != null)
                      Text("Autorizado: ${widget.pedido['segundo_recoge']}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text("�Es la persona registrada o el segundo autorizado?", style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                        ),
                        Switch(
                          value: _identidadVerificada,
                          onChanged: (val) {
                            setState(() => _identidadVerificada = val);
                          },
                          activeColor: Colors.orange,
                        )
                      ],
                    )
                  ],
                ),
              ),
            ),
          
          if (_haCambiado && (widget.userRol == 'vendedor' || widget.userRol == 'cajero' || widget.userRol == 'admin') && estado == 'pendiente')
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save, size: 18),
                  label: const Text("GUARDAR CANTIDADES"),
                  onPressed: _isSaving ? null : _guardarCambiosPedido,
                ),
              ),
            ),
            
          if (widget.userRol == 'despachador' && estado == 'pendiente')
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.local_shipping, size: 18),
                  label: const Text("DESPACHAR PEDIDO"),
                  onPressed: _isSaving ? null : _despacharPedido,
                ),
              ),
            ),

          if (estado == 'pendiente' && widget.userRol != 'despachador')
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text("CANCELAR PEDIDO"),
                  onPressed: () => _mostrarDialogoConfirmarCancelacion(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Modificado silenciosamente seg?n las instrucciones.

