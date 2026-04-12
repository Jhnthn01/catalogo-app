import 'package:flutter/material.dart';

import 'package:catalogo_digital_app/services/cart_service.dart';

class ResumenPedidoPage extends StatelessWidget {
  final Map<String, dynamic> datosUsuario;
  final double total;
  final List<CartItem> items;

  const ResumenPedidoPage({
    super.key,
    required this.datosUsuario,
    required this.total,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Resumen de Pedido"),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 80),
                  SizedBox(height: 10),
                  Text(
                    "¡PEDIDO REALIZADO!",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _buildSeccionTitulo("DATOS DE CONTACTO"),
            _buildDatoFila("Nombre:", datosUsuario['nombre'] ?? "No registrado"),
            _buildDatoFila(
                "Teléfono:", datosUsuario['telefono'] ?? "No registrado"),
            const Divider(color: Colors.white10, height: 30),
            _buildSeccionTitulo("PRODUCTOS"),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${item.cantidad}x ${item.nombre}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        "\$${(item.precio * item.cantidad).toStringAsFixed(2)}",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
            const Divider(color: Colors.white10, height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "TOTAL A PAGAR:",
                  style: TextStyle(
                      color: Colors.blue,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  "\$${total.toStringAsFixed(2)}",
                  style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Menciona tu nombre en caja para proceder con el pago y retiro de tus productos.",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12),
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/', (route) => false),
                child: const Text("VOLVER AL CATÁLOGO",
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccionTitulo(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(titulo,
          style: const TextStyle(
              color: Colors.grey, fontSize: 12, letterSpacing: 1.2)),
    );
  }

  Widget _buildDatoFila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(etiqueta,
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(width: 10),
          Text(valor,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
