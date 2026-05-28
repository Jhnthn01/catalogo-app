import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/features/orders/pedidos_entregados_page.dart';

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
          total_despachado,
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
          direccion_cliente,
          entregado_a,
          detalles_pedido (
            id,
            cantidad,
            precio_unitario,
            cantidad_despachada,
            productos (
              descripcion_1,
              upc
            )
          )
        ''');

      query = query.neq('estado', 'entregado').neq('estado', 'cancelado');

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
        appBar: AppBar(title: const Text("Pedidos Pendientes"), backgroundColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Pedidos Pendientes"),
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
  String? _entregadoA;
  late List<TextEditingController> _despachadaControllers;
  bool _mostrarDetallesAdicionales = false;

  @override
  void initState() {
    super.initState();
    _detalles = List.from(widget.pedido['detalles_pedido'] ?? []);
    _entregadoA = widget.pedido['entregado_a'];
    _despachadaControllers = _detalles.map((d) => TextEditingController(text: (d['cantidad_despachada'] ?? 0).toString())).toList();
  }

  @override
  void dispose() {
    for (var c in _despachadaControllers) {
      c.dispose();
    }
    super.dispose();
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
      _despachadaControllers[index].text = newQty.toString();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al guardar: $e", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _despacharPedido() async {
    if (_entregadoA == null || _entregadoA!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Debes seleccionar a quién se entrega el pedido", style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
      return;
    }

    // Validate: no empty or invalid fields, and total > 0
    double totalEntregado = 0;
    for (int i = 0; i < _detalles.length; i++) {
      final val = int.tryParse(_despachadaControllers[i].text.trim());
      if (val == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hay campos de cantidad entregada inválidos", style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
        return;
      }
      totalEntregado += val * double.parse(_detalles[i]['precio_unitario'].toString());
    }
    if (totalEntregado == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No puedes despachar un pedido con 0 productos entregados", style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isSaving = true);
    try {
      for (int i = 0; i < _detalles.length; i++) {
        final d = _detalles[i];
        final qty = int.tryParse(_despachadaControllers[i].text.trim()) ?? 0;
        if (qty > 0) {
          await Supabase.instance.client
              .from('detalles_pedido')
              .update({'cantidad_despachada': qty})
              .eq('id', d['id']);
        } else {
          await Supabase.instance.client
              .from('detalles_pedido')
              .delete()
              .eq('id', d['id']);
        }
      }
      await Supabase.instance.client
          .from('pedidos')
          .update({
            'estado': 'entregado',
            'total_despachado': totalEntregado,
            'entregado_a': _entregadoA
          })
          .eq('id', widget.pedido['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pedido marcado como entregado", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const PedidosEntregadosPage(),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error despachando pedido: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al despachar: $e", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancelarPedido(String motivo) async {
    try {
      await Supabase.instance.client
          .from('pedidos')
          .update({'estado': 'cancelado', 'motivo_cancelacion': motivo})
          .eq('id', widget.pedido['id'].toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pedido cancelado correctamente", style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent),
        );
        widget.onRefresh();
      }
    } catch (e) {
      debugPrint("Error al cancelar: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cancelar: $e", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _mostrarDialogoConfirmarCancelacion(BuildContext context) {
    final TextEditingController motivoCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 22),
                SizedBox(width: 8),
                Text("Cancelar Pedido", style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Esta acci\u00f3n es irreversible. Por favor indica el motivo de la cancelaci\u00f3n.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: motivoCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Motivo de la cancelaci\u00f3n",
                      labelStyle: const TextStyle(color: Colors.orangeAccent),
                      hintText: "M\u00ednimo 10 caracteres...",
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    validator: (val) {
                      if (val == null || val.trim().length < 10) {
                        return 'El motivo debe tener al menos 10 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  AnimatedOpacity(
                    opacity: motivoCtrl.text.trim().length < 10 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      "${motivoCtrl.text.trim().length}/10 caracteres m\u00ednimos",
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("VOLVER", style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: motivoCtrl.text.trim().length >= 10 ? Colors.redAccent : Colors.grey.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.cancel, size: 16, color: Colors.white),
                label: const Text("CONFIRMAR CANCELACI\u00d3N", style: TextStyle(color: Colors.white, fontSize: 12)),
                onPressed: motivoCtrl.text.trim().length >= 10
                    ? () {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(dialogContext);
                          _cancelarPedido(motivoCtrl.text.trim());
                        }
                      }
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEstadoChip(String estado) {
    Color color;
    switch (estado.toLowerCase()) {
      case 'pendiente': color = Colors.orange; break;
      case 'completado': color = Colors.green; break;
      case 'entregado': color = Colors.green; break;
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
    
    // Total based on delivered quantities (for despachador/admin)
    double totalEntregado = 0;
    bool canDespachar = true;
    for (int i = 0; i < _detalles.length; i++) {
      final parsed = int.tryParse(_despachadaControllers[i].text.trim());
      if (parsed == null) canDespachar = false;
      final qty = parsed ?? 0;
      totalEntregado += qty * double.parse(_detalles[i]['precio_unitario'].toString());
    }
    if (totalEntregado == 0) canDespachar = false;

    // Total based on ordered quantities (for non-despachador)
    double currentTotal = 0;
    for (var d in _detalles) {
      currentTotal += (d['cantidad'] as int) * double.parse(d['precio_unitario'].toString());
    }

    final double originalTotalDb = double.tryParse((widget.pedido['total'] ?? 0).toString()) ?? 0.0;
    final double despachadoTotalDb = double.tryParse((widget.pedido['total_despachado'] ?? originalTotalDb).toString()) ?? originalTotalDb;

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
            const SizedBox(height: 4),
            if (estado == 'pendiente') ...[
              if (widget.userRol == 'despachador' || widget.userRol == 'admin') ...[
                Text("Total pedido: S/.${currentTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  "Total entregado: S/.${totalEntregado.toStringAsFixed(2)}",
                  style: TextStyle(
                    color: totalEntregado > 0 ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ] else
                Text("Total: S/.${currentTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
            ] else ...[
              Text("Total pedido: S/.${originalTotalDb.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (estado == 'entregado') ...[
                const SizedBox(height: 2),
                Text(
                  "Total entregado: S/.${despachadoTotalDb.toStringAsFixed(2)}",
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ],
        ),
        trailing: _buildEstadoChip(estado),
        children: [
          if (widget.pedido['requiere_regularizacion'] == true)
            Container(
              width: double.infinity,
              color: Colors.redAccent.withValues(alpha: 0.2),
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
                // Tarjeta limpia del cliente titular (siempre visible, y expandible al presionar)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _mostrarDetallesAdicionales = !_mostrarDetallesAdicionales;
                    });
                  },
                  child: Card(
                    color: Colors.white.withValues(alpha: 0.05),
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("CONTACTO TITULAR / DATOS CLIENTE", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              Icon(
                                _mostrarDetallesAdicionales ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.person_outline, color: Colors.grey, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text("Nombre: ${widget.pedido['nombre_cliente'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, color: Colors.grey, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text("Dirección: ${widget.pedido['direccion_cliente'] ?? 'No especificada'}", style: const TextStyle(color: Colors.white70, fontSize: 13))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.phone_outlined, color: Colors.grey, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text("Teléfono: ${widget.pedido['telefono_cliente'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white70, fontSize: 13))),
                            ],
                          ),
                          
                          if (_mostrarDetallesAdicionales) ...[
                            const SizedBox(height: 12),
                            const Divider(color: Colors.white10, height: 1),
                            const SizedBox(height: 12),
                            const Text("LOGÍSTICA", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.badge_outlined, color: Colors.grey, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text("Documento: ${widget.pedido['tipo_documento'] ?? ''} ${widget.pedido['numero_documento'] ?? ''}", style: const TextStyle(color: Colors.white70, fontSize: 13))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today_outlined, color: Colors.grey, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text("Entrega: ${fechaEntrega != null ? DateFormat('dd/MM/yyyy hh:mm a').format(fechaEntrega) : 'No especificada'}", style: const TextStyle(color: Colors.white70, fontSize: 13))),
                              ],
                            ),
                            if (widget.pedido['segundo_recoge'] != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.people_outline, color: Colors.grey, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text("Segundo Autorizado: ${widget.pedido['segundo_recoge']}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13))),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Divider(color: Colors.white10, height: 1),
                            const SizedBox(height: 12),
                            const Text("FINANZAS", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.receipt_long_outlined, color: Colors.grey, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text("Comprobante: ${widget.pedido['tipo_comprobante'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white70, fontSize: 13))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.payment_outlined, color: Colors.grey, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text("Forma de pago:\n${(widget.pedido['forma_pago'] ?? '').toString().replaceAll(' | ', '\n')}", style: const TextStyle(color: Colors.white70, fontSize: 13))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.monetization_on_outlined, color: Colors.greenAccent, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text("TOTAL: S/.${currentTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                
                if ((widget.userRol == 'despachador' || widget.userRol == 'admin') && estado == 'pendiente') ...[
                  const SizedBox(height: 8),
                  const Text("A quién se entrega:", style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Cliente Principal: ${widget.pedido['nombre_cliente'] ?? 'No especificado'}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Checkbox(
                        value: _entregadoA == "Titular",
                        onChanged: (val) {
                          if (val == true) setState(() => _entregadoA = "Titular");
                        },
                        activeColor: Colors.blueAccent,
                      )
                    ],
                  ),
                  if (widget.pedido['segundo_recoge'] != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Segundo Autorizado: ${widget.pedido['segundo_recoge']}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        Checkbox(
                          value: _entregadoA == "Segundo Autorizado",
                          onChanged: (val) {
                            if (val == true) setState(() => _entregadoA = "Segundo Autorizado");
                          },
                          activeColor: Colors.blueAccent,
                        )
                      ],
                    ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          if (widget.userRol == 'despachador' || widget.userRol == 'admin')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: const [
                  Expanded(child: Text("PRODUCTO", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold))),
                  SizedBox(width: 8),
                  SizedBox(width: 45, child: Center(child: Text("PEDIDO", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)))),
                  SizedBox(width: 8),
                  SizedBox(width: 110, child: Center(child: Text("ENTREGADO", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)))),
                  SizedBox(width: 8),
                  SizedBox(width: 60, child: Center(child: Text("PRECIO", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
            
          ..._detalles.asMap().entries.map((entry) {
            final int index = entry.key;
            final detalle = entry.value;
            final int qtyOriginal = detalle['cantidad'];
            final int qtyDespachada = detalle['cantidad_despachada'] ?? 0;

            if (widget.userRol == 'despachador' || widget.userRol == 'admin') {
              final precio = double.parse(detalle['precio_unitario'].toString());
              final qtyEntregada = int.tryParse(_despachadaControllers[index].text.trim()) ?? 0;
              final subtotal = qtyEntregada * precio;
              final bool sinStock = detalle['requiere_regularizacion'] == true;
              final String nombreProducto = detalle['productos']?['descripcion_1'] ?? 'Producto Desconocido';
              final String? upc = detalle['productos']?['upc'];
              final String nombreCorto = nombreProducto.length > 10 ? '${nombreProducto.substring(0, 10)}...' : nombreProducto;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // PRODUCTO Column (warning icon + name + upc below)
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (sinStock)
                                GestureDetector(
                                  onTap: () => showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      backgroundColor: const Color(0xFF1E1E1E),
                                      title: const Row(children: [
                                        Icon(Icons.warning_amber, color: Colors.orange),
                                        SizedBox(width: 8),
                                        Text("Stock 0", style: TextStyle(color: Colors.white)),
                                      ]),
                                      content: const Text("Advertencia: Este producto se vendió sin stock en sistema. Verifique la existencia física antes de entregar.", style: TextStyle(color: Colors.white70)),
                                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("ENTENDIDO", style: TextStyle(color: Colors.blueAccent)))],
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      nombreCorto,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    if (upc != null && upc.isNotEmpty)
                                      Text(
                                        upc,
                                        style: const TextStyle(color: Colors.grey, fontSize: 9),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // PEDIDO
                        SizedBox(
                          width: 45,
                          child: Center(
                            child: Text("$qtyOriginal", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // ENTREGADO controls
                        if (estado == 'pendiente')
                          SizedBox(
                            width: 110,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () => _actualizarCantidadDespachada(index, qtyDespachada - 1),
                                  child: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 22),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 36,
                                  child: TextFormField(
                                    controller: _despachadaControllers[index],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                                    ),
                                    onChanged: (val) {
                                      final parsed = int.tryParse(val) ?? 0;
                                      setState(() {
                                        _detalles[index]['cantidad_despachada'] = parsed;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => _actualizarCantidadDespachada(index, qtyDespachada + 1),
                                  child: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 22),
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            width: 110,
                            child: Center(
                              child: Text("$qtyDespachada", style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        const SizedBox(width: 8),
                        // PRECIO (subtotal)
                        SizedBox(
                          width: 60,
                          child: Center(
                            child: Text(
                              "S/.${subtotal.toStringAsFixed(2)}",
                              style: TextStyle(
                                color: subtotal > 0 ? Colors.greenAccent : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 10),
                  ],
                ),
              );
            } else {
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
                        if ((widget.userRol == 'vendedor' || widget.userRol == 'cajero') && estado == 'pendiente')
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
                          
                        Text("Despachado: $qtyDespachada", style: const TextStyle(color: Colors.blueAccent, fontSize: 13)),
                      ],
                    )
                  ],
                ),
              );
            }
          }),
          

          if ((widget.userRol == 'despachador' || widget.userRol == 'admin') && estado == 'pendiente')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text("TOTAL ENTREGADO: ", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(
                    "S/.${totalEntregado.toStringAsFixed(2)}",
                    style: TextStyle(
                      color: totalEntregado > 0 ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          if (estado == 'entregado')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text("TOTAL DESPACHADO: ", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(
                    "S/.${despachadoTotalDb.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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
            
          if ((widget.userRol == 'despachador' || widget.userRol == 'admin') && estado == 'pendiente')
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canDespachar ? Colors.green : Colors.grey.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Icon(Icons.local_shipping, size: 18, color: canDespachar ? Colors.white : Colors.grey.shade400),
                  label: Text(
                    canDespachar ? "FINALIZAR DESPACHO" : "DESPACHO BLOQUEADO (total = 0)",
                    style: TextStyle(color: canDespachar ? Colors.white : Colors.grey.shade400),
                  ),
                  onPressed: (_isSaving || !canDespachar) ? null : _despacharPedido,
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

