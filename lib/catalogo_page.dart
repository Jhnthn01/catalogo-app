import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // Importante
import 'detalle_producto_page.dart';
import 'menu_lateral.dart';
import 'cart_service.dart';
import 'carrito_page.dart';

class CatalogoPage extends StatefulWidget {
  const CatalogoPage({super.key});

  @override
  _CatalogoPageState createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _productos = [];
  bool _isLoading = false;
  bool _isScanning = false; // Controla si se muestra la cámara
  String _searchQuery = "";
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProductos();
  }

  Future<void> _fetchProductos({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _productos = [];
      });
    }
    setState(() => _isLoading = true);
    try {
      var query = _supabase
          .from('productos')
          .select('id, sku, descripcion_1, precio_venta, costo');

      if (_searchQuery.isNotEmpty) {
        query = query.or('descripcion_1.ilike.%$_searchQuery%,sku.ilike.%$_searchQuery%');
      }

      final data = await query.order('descripcion_1', ascending: true);

      if (mounted) {
        setState(() {
          _productos = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      drawer: const MenuLateral(),
      appBar: AppBar(
  title: const Text("Catálogo de Productos"),
  backgroundColor: const Color(0xFF121212),
  actions: [
    // El "escuchador" detecta cambios desde cualquier parte de la app
    ValueListenableBuilder<int>(
      valueListenable: CartService().itemsCountNotifier,
      builder: (context, count, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CarritoPage()),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    ),
    const SizedBox(width: 8),
  ],
),
      body: Column(
        children: [
          // --- SECCIÓN DINÁMICA: BUSCADOR O CÁMARA ---
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isScanning ? _buildScanner() : _buildSearchBar(),
          ),

          // --- GRID DE PRODUCTOS ---
          Expanded(
            child: _productos.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.70,
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                    ),
                    itemCount: _productos.length,
                    itemBuilder: (context, index) => _buildProductCard(_productos[index]),
                  ),
          ),
        ],
      ),
    );
  }

  // WIDGET 1: EL BUSCADOR NORMAL
  Widget _buildSearchBar() {
    return Padding(
      key: const ValueKey(1),
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(15),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) {
            _searchQuery = val;
            _fetchProductos(refresh: true);
          },
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Buscar producto...",
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.search, color: Colors.blue),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.blue),
              onPressed: () => setState(() => _isScanning = true),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }

  // WIDGET 2: LA CÁMARA PARA ESCANEAR
  Widget _buildScanner() {
    return Padding(
      key: const ValueKey(2),
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 200, // Altura fija para el área de la cámara
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    final String code = barcodes.first.rawValue ?? "";
                    setState(() {
                      _isScanning = false;
                      _searchController.text = code;
                      _searchQuery = code;
                    });
                    _fetchProductos(refresh: true);
                  }
                },
              ),
              // Botón para cerrar la cámara manualmente
              Positioned(
                right: 10,
                top: 10,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _isScanning = false),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

Widget _buildProductCard(Map<String, dynamic> producto) {
  return Card(
    color: const Color(0xFF1E1E1E),
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetalleProductoPage(producto: producto),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Espacio para imagen (Placeholder si no hay)
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 40),
            ),
            const SizedBox(height: 10),
            Text(
              producto['descripcion_1'] ?? 'Sin nombre',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(), // Empuja el precio y botón al fondo
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Precio", style: TextStyle(color: Colors.grey, fontSize: 10)),
                    Text(
                      "\$${producto['precio_venta']}",
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                
                // BOTÓN DE AÑADIR RÁPIDO
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _mostrarDialogoCantidad(context, producto),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Icon(
                        Icons.add_shopping_cart_rounded,
                        color: Colors.blue,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  void _mostrarDialogoCantidad(BuildContext context, Map<String, dynamic> producto) {
  int cantidad = 1; // Empezamos con 1 por defecto

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder( // Usamos StatefulBuilder para que el contador funcione dentro del dialog
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              producto['descripcion_1'],
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Selecciona la cantidad", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                      onPressed: () {
                        if (cantidad > 1) setDialogState(() => cantidad--);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        "$cantidad",
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                      onPressed: () => setDialogState(() => cantidad++),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () {
                  CartService().agregarProducto(producto, cantidad);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("$cantidad x ${producto['descripcion_1']} añadido"),
                      backgroundColor: Colors.blueGrey.shade900,
                    ),
                  );
                },
                child: const Text("AÑADIR"),
              ),
            ],
          );
        },
      );
    },
  );
}
}