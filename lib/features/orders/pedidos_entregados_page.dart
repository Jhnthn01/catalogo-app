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

      return List<Map<String, dynamic>>.from(response);
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

          final list = snapshot.data!;

          return ListView.builder(
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Monto cobrado:",
                              style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              "S/.${finalTotal.toStringAsFixed(2)}",
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold),
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
          );
        },
      ),
    );
  }
}
