import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MisPedidosPage extends StatelessWidget {
  const MisPedidosPage({super.key});

  Future<List<Map<String, dynamic>>> _fetchPedidos() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      final response = await Supabase.instance.client
          .from('pedidos')
          .select('''
          id,
          total,
          estado,
          created_at,
          detalles_pedido (
            cantidad,
            precio_unitario,
            productos (
              descripcion_1
            )
          )
        ''')
          .eq('usuario_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("Error en Mis Pedidos: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Mis Pedidos"),
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
                "Aún no tienes pedidos",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final pedidos = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: pedidos.length,
            itemBuilder: (context, index) {
              final pedido = pedidos[index];
              final DateTime fecha = DateTime.parse(pedido['created_at']);

              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ExpansionTile(
                  iconColor: Colors.blue,
                  collapsedIconColor: Colors.white54,
                  title: Text(
                    "Pedido #${pedido['id'].toString().substring(0, 8)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    "${DateFormat('dd/MM/yyyy HH:mm').format(fecha)} - Total: \$${pedido['total']}",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: _buildEstadoChip(pedido['estado']),
                  children: [
                    const Divider(color: Colors.white10),
                    ...(pedido['detalles_pedido'] as List).map((detalle) {
                      return ListTile(
                        dense: true,
                        title: Text(
                          detalle['productos']['descripcion_1'],
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: Text(
                          "Cant: ${detalle['cantidad']}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      );
                    }),
                    if (pedido['estado'].toString().toLowerCase() == 'pendiente')
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text("CANCELAR PEDIDO"),
                            onPressed: () => _mostrarDialogoConfirmarCancelacion(
                              context,
                              pedido['id'].toString(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEstadoChip(String estado) {
    Color color;
    switch (estado.toLowerCase()) {
      case 'pendiente':
        color = Colors.orange;
        break;
      case 'completado':
        color = Colors.green;
        break;
      case 'cancelado':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        estado.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _mostrarDialogoConfirmarCancelacion(
    BuildContext context,
    String pedidoId,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "¿Cancelar pedido?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Esta acción notificará a la tienda. ¿Deseas continuar?",
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "VOLVER",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelarPedido(context, pedidoId);
            },
            child: const Text(
              "SÍ, CANCELAR",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelarPedido(BuildContext context, String pedidoId) async {
    try {
      await Supabase.instance.client
          .from('pedidos')
          .update({'estado': 'cancelado'})
          .eq('id', pedidoId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pedido cancelado correctamente")),
        );
      }
    } catch (e) {
      debugPrint("Error al cancelar: $e");
    }
  }
}
