import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/features/orders/detalle_pedido_page.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';
import 'package:catalogo_digital_app/features/orders/order_pdf_helper.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:printing/printing.dart';

class PedidosEntregadosPage extends StatefulWidget {
  const PedidosEntregadosPage({super.key});

  @override
  State<PedidosEntregadosPage> createState() => _PedidosEntregadosPageState();
}

class _PedidosEntregadosPageState extends State<PedidosEntregadosPage> {
  final _supabase = Supabase.instance.client;
  String? _userRol;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _fetchRol();
  }

  Future<void> _fetchRol() async {
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

  Future<List<Map<String, dynamic>>> _fetchPedidosEntregados() async {
    if (_userId == null) return [];

    try {
      var query = _supabase
          .from('pedidos')
          .select('''
          id,
          usuario_id,
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
              id,
              sku,
              upc,
              alu,
              descripcion_1,
              descripcion_2,
              marca
            )
          )
        ''');

      // Filter by entregado
      query = query.eq('estado', 'entregado');

      // If user is client, only show their own delivered orders
      if (_userRol != 'admin' && _userRol != 'despachador' && _userRol != 'gerente') {
        query = query.eq('usuario_id', _userId!);
      }

      // Filtrar por tienda activa
      final tiendaId = TiendaService().tiendaActivaId.value;
      if (tiendaId != null) {
        query = query.eq('tienda_id', tiendaId);
      }

      // Order by created_at or creado_en descending
      final response = await query.order('creado_en', ascending: false);
      final pedidos = List<Map<String, dynamic>>.from(response);

      // Obtener perfiles por usuario_id de forma independiente
      final usuarioIds = pedidos
          .map((p) => p['usuario_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> perfilesMap = {};
      if (usuarioIds.isNotEmpty) {
        final perfilesResponse = await _supabase
            .from('perfiles')
            .select('id, nombre, email')
            .inFilter('id', usuarioIds);
        for (final p in perfilesResponse) {
          perfilesMap[p['id'].toString()] = p;
        }
      }

      return pedidos.map((p) {
        final uid = p['usuario_id']?.toString();
        return {
          ...p,
          'perfiles': uid != null ? perfilesMap[uid] : null,
        };
      }).toList();
    } catch (e) {
      debugPrint("Error en Pedidos Entregados: $e");
      return [];
    }
  }

  Future<void> _mostrarDialogoImpresion(Map<String, dynamic> pedidoData, List<CartItem> itemsImpresion) async {
    String formatoSeleccionado = 'ticket';
    bool isGenerating = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Row(
                children: [
                  Icon(Icons.print_outlined, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Text("¿Imprimir o descargar?", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Elija el formato del comprobante para proceder:",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text("Ticketera (80mm)", style: TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: const Text("Formato compacto térmico", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          value: 'ticket',
                          groupValue: formatoSeleccionado,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => formatoSeleccionado = val);
                            }
                          },
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        RadioListTile<String>(
                          title: const Text("Hoja A4", style: TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: const Text("Diseño corporativo formal", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          value: 'a4',
                          groupValue: formatoSeleccionado,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => formatoSeleccionado = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  if (isGenerating) ...[
                    const SizedBox(height: 15),
                    const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text("Generando PDF...", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text("CERRAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.send, size: 16, color: Colors.white),
                  label: const Text("WhatsApp", style: TextStyle(color: Colors.white)),
                  onPressed: () => OrderPdfHelper.enviarWhatsApp(dialogContext, pedidoData),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.download, size: 16, color: Colors.white),
                  label: const Text("PDF", style: TextStyle(color: Colors.white)),
                  onPressed: isGenerating
                      ? null
                      : () async {
                          setDialogState(() => isGenerating = true);
                          try {
                            Uint8List bytes;
                            if (formatoSeleccionado == 'a4') {
                              bytes = await OrderPdfHelper.generateA4(pedido: pedidoData, items: itemsImpresion);
                            } else {
                              bytes = await OrderPdfHelper.generateTicket(pedido: pedidoData, items: itemsImpresion);
                            }
                            final idCorto = pedidoData['id'].toString().substring(0, 8).toUpperCase();
                            await Printing.sharePdf(bytes: bytes, filename: 'pedido_$idCorto.pdf');
                          } catch (e) {
                            debugPrint("Error sharing pdf: $e");
                          } finally {
                            setDialogState(() => isGenerating = false);
                          }
                        },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.print, size: 16, color: Colors.white),
                  label: const Text("IMPRIMIR", style: TextStyle(color: Colors.white)),
                  onPressed: isGenerating
                      ? null
                      : () async {
                          setDialogState(() => isGenerating = true);
                          try {
                            Uint8List bytes;
                            if (formatoSeleccionado == 'a4') {
                              bytes = await OrderPdfHelper.generateA4(pedido: pedidoData, items: itemsImpresion);
                            } else {
                              bytes = await OrderPdfHelper.generateTicket(pedido: pedidoData, items: itemsImpresion);
                            }
                            await Printing.layoutPdf(onLayout: (format) async => bytes);
                          } catch (e) {
                            debugPrint("Error printing: $e");
                          } finally {
                            setDialogState(() => isGenerating = false);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _filterId = '';
  String _filterVendedor = '';

  @override
  Widget build(BuildContext context) {
    if (_userRol == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          "Pedidos Entregados",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: const MenuLateral(),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchPedidosEntregados(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No hay pedidos entregados",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            );
          }

          final todos = snapshot.data!;

          // Extraer vendedores únicos para el dropdown
          final Set<String> vendedoresSet = {};
          for (var p in todos) {
            final perfiles = p['perfiles'];
            if (perfiles is Map) {
              final n = perfiles['nombre']?.toString().trim();
              final e = perfiles['email']?.toString().trim();
              if (n != null && n.isNotEmpty) {
                vendedoresSet.add(n);
              } else if (e != null && e.isNotEmpty) {
                vendedoresSet.add(e);
              }
            }
          }
          final List<String> vendedoresList = vendedoresSet.toList()..sort();

          // Filtrar lista
          final list = todos.where((p) {
            if (_filterId.trim().isNotEmpty) {
              final idStr = (p['id'] ?? '').toString().toLowerCase();
              final numCliente = (p['nombre_cliente'] ?? '').toString().toLowerCase();
              final term = _filterId.trim().toLowerCase();
              if (!idStr.contains(term) && !numCliente.contains(term)) return false;
            }
            if (_filterVendedor.trim().isNotEmpty) {
              final perfiles = p['perfiles'];
              String vend = "Sistema / Sin Asignar";
              if (perfiles is Map) {
                final n = perfiles['nombre']?.toString().trim();
                final e = perfiles['email']?.toString().trim();
                if (n != null && n.isNotEmpty) vend = n;
                else if (e != null && e.isNotEmpty) vend = e;
              }
              if (vend != _filterVendedor) return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              // Barra de Filtros
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                color: const Color(0xFF1E1E1E),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        onChanged: (val) => setState(() => _filterId = val),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Nº Pedido / Cliente...",
                          hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                          prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _filterVendedor.isEmpty ? null : _filterVendedor,
                            hint: const Text("Vendedor", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2A2A2A),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
                            items: [
                              const DropdownMenuItem<String>(
                                value: "",
                                child: Text("Todos vendedores", style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ),
                              ...vendedoresList.map((v) => DropdownMenuItem<String>(
                                    value: v,
                                    child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: (val) => setState(() => _filterVendedor = val ?? ""),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text(
                          "No hay pedidos que coincidan con el filtro",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final pedido = list[index];
                          final DateTime date = DateTime.parse(pedido['creado_en'] ?? pedido['created_at']).toLocal();
                          final double originalTotal = double.tryParse((pedido['total'] ?? 0).toString()) ?? 0.0;
                          final double finalTotal = double.tryParse((pedido['total_despachado'] ?? originalTotal).toString()) ?? originalTotal;
                          final String clientName = pedido['nombre_cliente'] ?? 'Sin Nombre';
                          final String entregadoA = pedido['entregado_a'] ?? 'No especificado';

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: const BorderSide(color: Colors.white10),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              trailing: IconButton(
                                icon: const Icon(Icons.print, color: Colors.blueAccent, size: 24),
                                tooltip: 'Reimprimir / Descargar',
                                onPressed: () {
                                  final details = pedido['detalles_pedido'] as List<dynamic>? ?? [];
                                  final itemsImpresion = details.map((d) {
                                    return CartItem(
                                      id: d['id'].toString(),
                                      nombre: d['productos']?['descripcion_1']?.toString() ?? 'Producto',
                                      precio: double.tryParse(d['precio_unitario'].toString()) ?? 0.0,
                                      cantidad: (d['cantidad_despachada'] ?? d['cantidad']) as int,
                                    );
                                  }).toList();
                                  _mostrarDialogoImpresion(pedido, itemsImpresion);
                                },
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Pedido #${pedido['id'].toString().substring(0, 8)}",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                                    ),
                                    child: const Text(
                                      "ENTREGADO",
                                      style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Fecha: ${DateFormat('dd/MM/yyyy hh:mm a').format(date)}",
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Cliente: $clientName",
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "Vendedor: ${pedido['perfiles'] != null && (pedido['perfiles']['nombre']?.toString().trim().isNotEmpty ?? false) ? pedido['perfiles']['nombre'] : (pedido['perfiles']?['email'] ?? 'Sistema / Sin Asignar')}",
                                      style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Text("Recogió: ", style: TextStyle(color: Colors.grey, fontSize: 11)),
                                        Text(
                                          entregadoA,
                                          style: TextStyle(
                                            color: entregadoA == 'Titular' ? Colors.blueAccent : Colors.orangeAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Text(
                                          "Original: S/.${originalTotal.toStringAsFixed(2)}",
                                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          "Entregado: S/.${finalTotal.toStringAsFixed(2)}",
                                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DetallePedidoPage(
                                      pedido: pedido,
                                      userRol: _userRol!,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
