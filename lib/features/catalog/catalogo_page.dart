import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/features/cart/carrito_page.dart';
import 'package:catalogo_digital_app/features/catalog/detalle_producto_page.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';

class CatalogoPage extends StatefulWidget {
  const CatalogoPage({super.key});

  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _productos = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String _searchQuery = "";
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _hasMore = true;
  int _paginaActual = 0;
  final int _tamanhoPagina = 25;
  int _fetchId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchProductos(refresh: true);
    });
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _fetchProductos();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProductos({bool refresh = false}) async {
    if (refresh) {
      _paginaActual = 0;
      _hasMore = true;
      _productos.clear();
      if (mounted) setState(() {});
    } else if (_isLoading || !_hasMore) {
      return;
    }

    if (!mounted) return;

    final int currentFetchId = ++_fetchId;
    setState(() => _isLoading = true);
    
    try {
      final desde = _paginaActual * _tamanhoPagina;
      final hasta = desde + _tamanhoPagina - 1;

      var query = _supabase
          .from('productos')
          .select('id, sku, upc, alu, descripcion_1, precio_venta, costo, inventario(stock)');

      if (_searchQuery.isNotEmpty) {
        query = query.or(
            'descripcion_1.ilike.%$_searchQuery%,sku.ilike.%$_searchQuery%,upc.ilike.%$_searchQuery%,alu.ilike.%$_searchQuery%');
      }

      final List<dynamic> data = await query
          .order('descripcion_1', ascending: true)
          .range(desde, hasta);

      if (!mounted || currentFetchId != _fetchId) return;

      setState(() {
        _productos.addAll(data);
        _paginaActual++;
        _isLoading = false;
        if (data.length < _tamanhoPagina) _hasMore = false;
      });
    } catch (e) {
      if (mounted && currentFetchId == _fetchId) {
        setState(() => _isLoading = false);
      }
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
          ValueListenableBuilder<int>(
            valueListenable: CartService().itemsCountNotifier,
            builder: (context, count, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined,
                        color: Colors.white),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const CarritoPage()),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isScanning ? _buildScanner() : _buildSearchBar(),
          ),
          Expanded(
            child: _productos.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _productos.isEmpty && !_isLoading
                    ? const Center(
                        child: Text(
                          'No se encontraron productos.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        itemCount: _productos.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _productos.length) {
                             return const Center(
                               child: Padding(
                                 padding: EdgeInsets.all(15), 
                                 child: CircularProgressIndicator(strokeWidth: 2)
                               )
                             );
                          }
                          return _buildProductCard(_productos[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildScanner() {
    return Padding(
      key: const ValueKey(2),
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 200,
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
    int totalStock = 0;
    if (producto['inventario'] != null && producto['inventario'] is List) {
      for (var inv in producto['inventario']) {
         totalStock += (inv['stock'] as num?)?.toInt() ?? 0;
      }
    }

    final String upcTexto = producto['upc'] ?? producto['sku'] ?? 'Sin código';

    return Card(
      color: const Color(0xFF1E1E1E),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetalleProductoPage(producto: producto),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              // Info Principal
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto['descripcion_1'] ?? 'Sin nombre',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "UPC: $upcTexto",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Precio, Stock y Botón
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "\$${producto['precio_venta'] ?? '0.00'}",
                    style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Stock: $totalStock",
                    style: TextStyle(
                        color: totalStock > 0 ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _mostrarDialogoCantidad(context, producto),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.add_shopping_cart_rounded, color: Colors.blue, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoCantidad(
      BuildContext context, Map<String, dynamic> producto) {
    int cantidad = 1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                producto['descripcion_1'],
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Selecciona la cantidad",
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.redAccent),
                        onPressed: () {
                          if (cantidad > 1) setDialogState(() => cantidad--);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "$cantidad",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline,
                            color: Colors.greenAccent),
                        onPressed: () => setDialogState(() => cantidad++),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCELAR",
                      style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue),
                  onPressed: () {
                    CartService().agregarProducto(producto, cantidad);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            "$cantidad x ${producto['descripcion_1']} añadido"),
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
