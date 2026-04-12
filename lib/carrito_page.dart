import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_service.dart';

class CarritoPage extends StatefulWidget {
  const CarritoPage({super.key});

  @override
  State<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends State<CarritoPage> {
  final cart = CartService();

  void _refrescar() => setState(() {});

  Future<void> _confirmarPedido() async {
    if (cart.items.isEmpty) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      
      final pedido = await Supabase.instance.client.from('pedidos').insert({
        'usuario_id': user?.id,
        'total': cart.total,
        'estado': 'pendiente',
      }).select().single();

      final detalles = cart.items.map((item) => {
        'pedido_id': pedido['id'],
        'producto_id': item.id,
        'cantidad': item.cantidad,
        'precio_unitario': item.precio,
      }).toList();

      await Supabase.instance.client.from('detalles_pedido').insert(detalles);

      cart.limpiar();
      if (mounted) {
        _mostrarExito();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _mostrarExito() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("¡Orden Generada!", style: TextStyle(color: Colors.white)),
        content: const Text("Tu pedido ha sido registrado. Paga en caja al llegar a la tienda.", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text("ENTENDIDO", style: TextStyle(color: Colors.blue)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Resumen de Pedido"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: cart.items.isEmpty
          ? _buildCarritoVacio()
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(15),
                    itemCount: cart.items.length,
                    itemBuilder: (context, i) {
                      final item = cart.items[i];
                      return _buildCartItem(item);
                    },
                  ),
                ),
                _buildFooter(),
              ],
            ),
    );
  }

  Widget _buildCarritoVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.remove_shopping_cart_outlined, size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 15),
          const Text("Tu carrito está vacío", style: TextStyle(color: Colors.grey, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          // Info del producto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 5),
                Text("\$${item.precio.toStringAsFixed(2)} c/u", style: const TextStyle(color: Colors.blue, fontSize: 14)),
              ],
            ),
          ),
          
          // Controles de cantidad
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
                onPressed: () {
                  cart.actualizarCantidad(item.id, item.cantidad - 1);
                  _refrescar();
                },
              ),
              Text("${item.cantidad}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                onPressed: () {
                  cart.actualizarCantidad(item.id, item.cantidad + 1);
                  _refrescar();
                },
              ),
              // Botón eliminar
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  cart.eliminarProducto(item.id);
                  _refrescar();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total Estimado", style: TextStyle(color: Colors.grey, fontSize: 16)),
                Text("\$${cart.total.toStringAsFixed(2)}", 
                  style: const TextStyle(color: Colors.blue, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _confirmarPedido,
                child: const Text("CONFIRMAR MI PEDIDO", 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}