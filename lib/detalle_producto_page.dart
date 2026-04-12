import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'menu_lateral.dart';

class DetalleProductoPage extends StatefulWidget {
  final Map<String, dynamic> producto;

  const DetalleProductoPage({super.key, required this.producto});

  @override
  State<DetalleProductoPage> createState() => _DetalleProductoPageState();
}

class _DetalleProductoPageState extends State<DetalleProductoPage> {
  late TextEditingController _nameController;
  late TextEditingController _skuController;
  late TextEditingController _costoController;
  late TextEditingController _precioVentaController;

  int _cantidadAReservar = 0;
  double _totalVenta = 0.0;
  List<dynamic> _stocks = [];
  String userRol = 'cliente';
  
  // NUEVA VARIABLE: Controla si se puede editar o no
  bool _modoEdicion = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.producto['descripcion_1']);
    _skuController = TextEditingController(text: widget.producto['sku']);
    _costoController = TextEditingController(
      text: widget.producto['costo']?.toString() ?? '0.0',
    );
    _precioVentaController = TextEditingController(
      text: widget.producto['precio_venta']?.toString() ?? '0.0',
    );
    
    _checkUserRole();
    _fetchStock();
    _calcularTotal();
  }

  Future<void> _fetchStock() async {
    try {
      final data = await Supabase.instance.client
          .from('inventario')
          .select('stock, tiendas(codigo_tienda, nombre)')
          .eq('producto_id', widget.producto['id']);
      setState(() => _stocks = data);
    } catch (e) {
      debugPrint("Error cargando stock: $e");
    }
  }

  Future<void> _checkUserRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final data = await Supabase.instance.client
          .from('perfiles')
          .select('rol')
          .eq('id', user.id)
          .single();
      setState(() => userRol = data['rol']);
    }
  }

  void _calcularTotal() {
    double precio = double.tryParse(_precioVentaController.text) ?? 0.0;
    setState(() => _totalVenta = precio * _cantidadAReservar);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _costoController.dispose();
    _precioVentaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool esPersonal = (userRol == 'admin' || userRol == 'trabajador');

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      drawer: const MenuLateral(),
      appBar: AppBar(
        title: const Text("Detalle de Producto"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // SWITCH DE MODO EDICIÓN (Solo para Admin/Empleado)
          if (esPersonal)
            Row(
              children: [
                const Text("Editar", style: TextStyle(fontSize: 12)),
                Switch(
                  value: _modoEdicion,
                  activeColor: Colors.blue,
                  onChanged: (val) {
                    setState(() => _modoEdicion = val);
                  },
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // El nombre solo es editable si el switch está ON
            _buildTextField("Nombre del Producto", _nameController, enabled: _modoEdicion),
            const SizedBox(height: 20),
            _buildTextField("SKU", _skuController, enabled: false), // SKU nunca se edita por seguridad
            
            const SizedBox(height: 20),
            const Text("STOCK POR TIENDA", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            ..._stocks.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _buildTextField(
                "Tienda: ${s['tiendas']['nombre']}", 
                TextEditingController(text: s['stock'].toString()),
                enabled: false // El stock se edita desde otra lógica de inventario
              ),
            )).toList(),

            const SizedBox(height: 20),
            
            // Costo visible para personal, editable solo en modo edición
            if (esPersonal)
              _buildTextField("COSTO", _costoController, enabled: _modoEdicion),
            
            const SizedBox(height: 20),
            
            // Precio de venta editable solo en modo edición
            _buildTextField(
              "PRECIO VENTA PÚBLICO", 
              _precioVentaController,
              enabled: _modoEdicion,
              onChanged: (v) => _calcularTotal(),
            ),
            
            const Divider(height: 40, color: Colors.white10),

            // SECCIÓN DE COMPRA/CARRITO (Siempre habilitada para todos)
            const Text("COMPRAS / PEDIDOS", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            const Text("CANTIDAD A AÑADIR", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("$_cantidadAReservar", style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                        onPressed: () {
                          if (_cantidadAReservar > 0) {
                            setState(() => _cantidadAReservar--);
                            _calcularTotal();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                        onPressed: () {
                          setState(() => _cantidadAReservar++);
                          _calcularTotal();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            _buildTextField(
              "TOTAL PRODUCTOS",
              TextEditingController(text: "\$ ${_totalVenta.toStringAsFixed(2)}"),
              enabled: false,
            ),

            const SizedBox(height: 40),
            
            // BOTONES DE ACCIÓN
            SizedBox(
              width: double.infinity,
              child: _modoEdicion && userRol == 'admin' 
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.all(15)),
                    onPressed: _guardarCambios,
                    child: const Text("GUARDAR CAMBIOS EN INVENTARIO"),
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(15)),
                    onPressed: _cantidadAReservar > 0 ? () {
                      // Lógica de añadir al carrito
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Añadido al carrito")));
                    } : null,
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text("AÑADIR AL CARRITO"),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // Lógica para guardar datos en Supabase
  Future<void> _guardarCambios() async {
    try {
      await Supabase.instance.client
          .from('productos')
          .update({
            'descripcion_1': _nameController.text,
            'precio_venta': double.tryParse(_precioVentaController.text),
            'costo': double.tryParse(_costoController.text),
          })
          .eq('id', widget.producto['id']);

      if (mounted) {
        setState(() => _modoEdicion = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Producto actualizado correctamente"))
        );
      }
    } catch (e) {
      debugPrint("Error al guardar: $e");
    }
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool enabled = true, Function(String)? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          style: TextStyle(color: enabled ? Colors.white : Colors.white54),
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled ? Colors.grey.shade900 : Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}