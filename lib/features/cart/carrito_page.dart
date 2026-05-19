import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/features/cart/resumen_pedido_page.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';

class CarritoPage extends StatefulWidget {
  const CarritoPage({super.key});

  @override
  State<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends State<CarritoPage> {
  final cart = CartService();

  final TextEditingController _nombreClienteController = TextEditingController();
  final TextEditingController _formaPagoController = TextEditingController(text: 'Efectivo');
  final TextEditingController _segundoRecogeController = TextEditingController();
  final TextEditingController _fechaDateController = TextEditingController();
  TimeOfDay? _horaEntrega;

  @override
  void dispose() {
    _nombreClienteController.dispose();
    _formaPagoController.dispose();
    _segundoRecogeController.dispose();
    _fechaDateController.dispose();
    super.dispose();
  }

  void _refrescar() => setState(() {});

  Future<void> _confirmarPedido() async {
    if (cart.items.isEmpty) return;

    final nombreCliente = _nombreClienteController.text.trim();
    final dateStr = _fechaDateController.text.trim();
    if (nombreCliente.isEmpty || dateStr.isEmpty || _horaEntrega == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: Nombre de cliente, fecha y hora de entrega son obligatorios"),
          backgroundColor: Colors.redAccent,
      ));
      return;
    }

    DateTime parsedDate;
    try {
      parsedDate = DateFormat('dd/MM/yyyy').parseStrict(dateStr);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: Formato inválido (dd/mm/yyyy) o fecha inexistente"),
          backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (parsedDate.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: La fecha no puede ser en el pasado"),
          backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final DateTime fechaEntregaFinal = DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      _horaEntrega!.hour,
      _horaEntrega!.minute,
    );

    try {
      final user = Supabase.instance.client.auth.currentUser;

      final perfilData = await Supabase.instance.client
          .from('perfiles')
          .select()
          .eq('id', user!.id)
          .single();

      final pedido = await Supabase.instance.client.from('pedidos').insert({
        'usuario_id': user.id,
        'total': cart.total,
        'estado': 'pendiente',
        'nombre_cliente': nombreCliente,
        'forma_pago': _formaPagoController.text.trim(),
        'fecha_entrega': fechaEntregaFinal.toIso8601String(),
        'segundo_recoge': _segundoRecogeController.text.trim().isNotEmpty ? _segundoRecogeController.text.trim() : null,
      }).select().single();

      final detalles = cart.items
          .map((item) => {
                'pedido_id': pedido['id'],
                'producto_id': item.id,
                'cantidad': item.cantidad,
                'precio_unitario': item.precio,
              })
          .toList();

      await Supabase.instance.client.from('detalles_pedido').insert(detalles);

      final itemsResumen = List<CartItem>.from(cart.items);
      final totalResumen = cart.total;

      cart.limpiar();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResumenPedidoPage(
              datosUsuario: perfilData,
              total: totalResumen,
              items: itemsResumen,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")));
    }
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
                  child: ListView(
                    padding: const EdgeInsets.all(15),
                    children: [
                      ...cart.items.map((item) => _buildCartItem(item)),
                      const SizedBox(height: 20),
                      const Text("Datos del Pedido", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      _buildTextField("Nombre del Cliente *", _nombreClienteController),
                      const SizedBox(height: 10),
                      _buildTextField("Forma de Pago", _formaPagoController),
                      const SizedBox(height: 10),
                      _buildTextField("Segundo a Recoger (Opcional)", _segundoRecogeController),
                      const SizedBox(height: 10),
                      _buildDateTimePicker(),
                      const SizedBox(height: 20),
                    ],
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
          Icon(Icons.remove_shopping_cart_outlined,
              size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 15),
          const Text("Tu carrito está vacío",
              style: TextStyle(color: Colors.grey, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildDateTimePicker() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _fechaDateController,
            keyboardType: TextInputType.datetime,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
              _DateTextFormatter(),
            ],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "Fecha (dd/mm/yyyy) *",
              labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_month, color: Colors.blue),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Colors.blue,
                            onPrimary: Colors.white,
                            surface: Color(0xFF1E1E1E),
                            onSurface: Colors.white,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    final formattedDate = DateFormat('dd/MM/yyyy').format(date);
                    _fechaDateController.text = formattedDate;
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () async {
              final List<TimeOfDay> allowedTimes = [];
              for (int h = 7; h <= 18; h++) {
                allowedTimes.add(TimeOfDay(hour: h, minute: 0));
                if (h < 18) allowedTimes.add(TimeOfDay(hour: h, minute: 30));
              }

              final time = await showDialog<TimeOfDay>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text("Hora (07:00 - 18:00)", style: TextStyle(color: Colors.white, fontSize: 16)),
                    content: SizedBox(
                      width: double.maxFinite,
                      height: 300,
                      child: ListView.builder(
                        itemCount: allowedTimes.length,
                        itemBuilder: (context, index) {
                          final t = allowedTimes[index];
                          final isAM = t.hour < 12;
                          final displayHour = t.hour == 12 ? 12 : t.hour % 12;
                          final hStr = displayHour == 0 ? "12" : displayHour.toString().padLeft(2, '0');
                          final mStr = t.minute.toString().padLeft(2, '0');
                          final amPm = isAM ? "AM" : "PM";
                          return ListTile(
                            title: Text("$hStr:$mStr $amPm", style: const TextStyle(color: Colors.white70)),
                            onTap: () => Navigator.pop(context, t),
                          );
                        },
                      ),
                    ),
                  );
                },
              );

              if (time != null) {
                setState(() => _horaEntrega = time);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _horaEntrega == null 
                        ? "Hora *" 
                        : "${_horaEntrega!.hour == 12 ? 12 : _horaEntrega!.hour % 12 == 0 ? 12 : _horaEntrega!.hour % 12}:${_horaEntrega!.minute.toString().padLeft(2, '0')} ${_horaEntrega!.hour < 12 ? 'AM' : 'PM'}",
                    style: TextStyle(color: _horaEntrega == null ? Colors.grey : Colors.white, fontSize: 13),
                  ),
                  const Icon(Icons.access_time, color: Colors.blue, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 5),
                Text("\$${item.precio.toStringAsFixed(2)} c/u",
                    style: const TextStyle(color: Colors.blue, fontSize: 14)),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.grey),
                onPressed: () {
                  cart.actualizarCantidad(item.id, item.cantidad - 1);
                  _refrescar();
                },
              ),
              GestureDetector(
                onTap: () async {
                  final TextEditingController qtyController =
                      TextEditingController(text: item.cantidad.toString());
                  await showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        backgroundColor: const Color(0xFF2C2C2C),
                        title: const Text("Editar Cantidad",
                            style: TextStyle(color: Colors.white)),
                        content: TextField(
                          controller: qtyController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue)),
                            enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.grey)),
                          ),
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("CANCELAR",
                                style: TextStyle(color: Colors.grey)),
                          ),
                          TextButton(
                            onPressed: () {
                              final int? newQty =
                                  int.tryParse(qtyController.text);
                              if (newQty != null && newQty >= 0) {
                                cart.actualizarCantidad(item.id, newQty);
                                _refrescar();
                              }
                              Navigator.pop(context);
                            },
                            child: const Text("GUARDAR",
                                style: TextStyle(color: Colors.blue)),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.blue.withOpacity(0.5))),
                  child: Text(
                    "${item.cantidad}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                onPressed: () {
                  cart.actualizarCantidad(item.id, item.cantidad + 1);
                  _refrescar();
                },
              ),
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
                const Text("Total Estimado",
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                Text(
                  "\$${cart.total.toStringAsFixed(2)}",
                  style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _confirmarPedido,
                child: const Text(
                  "CONFIRMAR MI PEDIDO",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;

    text = text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.length > 8) {
      text = text.substring(0, 8);
    }

    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 2 || i == 4) {
        formatted += '/';
      }
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
