import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DetallePedidoPage extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String userRol;

  const DetallePedidoPage({
    super.key,
    required this.pedido,
    required this.userRol,
  });

  @override
  Widget build(BuildContext context) {
    final DateTime fechaCreacion = DateTime.parse(pedido['creado_en'] ?? pedido['created_at'] ?? DateTime.now().toString()).toLocal();
    final DateTime? fechaEntrega = pedido['fecha_entrega'] != null ? DateTime.parse(pedido['fecha_entrega']).toLocal() : null;
    final String estado = (pedido['estado'] ?? 'pendiente').toString().toLowerCase();

    final List<dynamic> detalles = pedido['detalles_pedido'] ?? [];

    double totalPedido = 0;
    double totalEntregado = 0;
    for (var d in detalles) {
      final double precio = double.tryParse(d['precio_unitario'].toString()) ?? 0.0;
      final int cant = d['cantidad'] ?? 0;
      final int cantDesp = d['cantidad_despachada'] ?? 0;
      totalPedido += cant * precio;
      totalEntregado += cantDesp * precio;
    }

    final double originalTotalDb = double.tryParse((pedido['total'] ?? 0).toString()) ?? 0.0;
    final double despachadoTotalDb = double.tryParse((pedido['total_despachado'] ?? originalTotalDb).toString()) ?? originalTotalDb;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(
          "Pedido #${pedido['id'].toString().substring(0, 8)}",
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            _buildStatusCard(estado, fechaCreacion, fechaEntrega),
            const SizedBox(height: 16),

            // Client Info Card
            _buildSectionHeader("DETALLES DEL CLIENTE"),
            const SizedBox(height: 8),
            _buildClientCard(),
            const SizedBox(height: 16),

            // Finance Card
            _buildSectionHeader("FINANZAS & DOCUMENTOS"),
            const SizedBox(height: 8),
            _buildFinanceCard(originalTotalDb, despachadoTotalDb, totalPedido, totalEntregado),
            const SizedBox(height: 16),

            // Products Card
            _buildSectionHeader("PRODUCTOS DETALLADOS"),
            const SizedBox(height: 8),
            _buildProductsCard(detalles),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildStatusCard(String estado, DateTime creado, DateTime? entrega) {
    Color statusColor;
    switch (estado) {
      case 'pendiente':
        statusColor = Colors.orange;
        break;
      case 'completado':
      case 'entregado':
        statusColor = Colors.green;
        break;
      case 'despachado':
        statusColor = Colors.blue;
        break;
      case 'cancelado':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Estado del Pedido",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(
                  estado.toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Text(
            "Creado: ${DateFormat('dd/MM/yyyy hh:mm a').format(creado)}",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (entrega != null) ...[
            const SizedBox(height: 4),
            Text(
              "Entrega programada: ${DateFormat('dd/MM/yyyy hh:mm a').format(entrega)}",
              style: const TextStyle(color: Colors.blueAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClientCard() {
    final String nombre = pedido['nombre_cliente'] ?? 'No especificado';
    final String direccion = pedido['direccion_cliente'] ?? 'No especificada';
    final String documento = "${pedido['tipo_documento'] ?? ''} ${pedido['numero_documento'] ?? ''}".trim();
    final String telefono = pedido['telefono_cliente'] ?? 'No especificado';
    final String? segundo = pedido['segundo_recoge'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(Icons.person_outline, "Titular", nombre),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.location_on_outlined, "Dirección", direccion),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.badge_outlined, "Documento", documento.isEmpty ? "No especificado" : documento),
          const SizedBox(height: 10),
          _buildInfoRow(Icons.phone_outlined, "Teléfono", telefono),
          if (segundo != null && segundo.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.people_outline, "Segundo Autorizado", segundo, color: Colors.orangeAccent),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color color = Colors.white}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinanceCard(double originalDb, double despachadoDb, double calcPedido, double calcEntregado) {
    final String comprobante = pedido['tipo_comprobante'] ?? 'No especificado';
    final String formaPago = (pedido['forma_pago'] ?? '').toString().replaceAll(' | ', '\n');
    final String? entregadoA = pedido['entregado_a'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Tipo de Comprobante", style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(comprobante, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Forma de Pago", style: TextStyle(color: Colors.grey, fontSize: 12)),
              Flexible(
                child: Text(
                  formaPago.isEmpty ? 'No especificada' : formaPago,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                ),
              ),
            ],
          ),
          if (entregadoA != null && entregadoA.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Entregado a", style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text(
                  entregadoA,
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL PEDIDO ORIGINAL:", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(
                "S/.${originalDb > 0 ? originalDb.toStringAsFixed(2) : calcPedido.toStringAsFixed(2)}",
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL DESPACHADO FINAL:", style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              Text(
                "S/.${despachadoDb > 0 ? despachadoDb.toStringAsFixed(2) : calcEntregado.toStringAsFixed(2)}",
                style: const TextStyle(color: Colors.greenAccent, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductsCard(List<dynamic> detalles) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: const [
                Expanded(child: Text("PRODUCTO", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold))),
                SizedBox(width: 8),
                SizedBox(width: 45, child: Center(child: Text("PED.", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)))),
                SizedBox(width: 8),
                SizedBox(width: 45, child: Center(child: Text("ENTR.", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)))),
                SizedBox(width: 8),
                SizedBox(width: 60, child: Center(child: Text("PRECIO", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)))),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: detalles.length,
            itemBuilder: (context, index) {
              final d = detalles[index];
              final String name = d['productos']?['descripcion_1'] ?? 'Producto Desconocido';
              final String? upc = d['productos']?['upc'];
              final int qtyOriginal = d['cantidad'] ?? 0;
              final int qtyDespachada = d['cantidad_despachada'] ?? 0;
              final double precio = double.tryParse(d['precio_unitario'].toString()) ?? 0.0;

              final String shortName = name.length > 12 ? '${name.substring(0, 12)}...' : name;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                shortName,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              if (upc != null && upc.isNotEmpty)
                                Text(
                                  upc,
                                  style: const TextStyle(color: Colors.grey, fontSize: 9),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 45,
                          child: Center(
                            child: Text(
                              "$qtyOriginal",
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 45,
                          child: Center(
                            child: Text(
                              "$qtyDespachada",
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: Center(
                            child: Text(
                              "S/.${precio.toStringAsFixed(2)}",
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index < detalles.length - 1)
                    const Divider(color: Colors.white10, height: 1),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
