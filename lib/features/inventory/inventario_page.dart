import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/features/catalog/detalle_producto_page.dart';
import 'package:catalogo_digital_app/widgets/filtros_jerarquia.dart';

class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final List<Map<String, dynamic>> _productos = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';

  bool _isScanning = false;
  bool _isLoading = false;
  bool _hasMore = true;
  int _paginaActual = 0;
  final int _tamanhoPagina = 25;
  int _fetchId = 0;

  String? _catFiltro;
  String? _claseFiltro;
  String? _subClaseFiltro;

  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cargarMasProductos();
    });
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _cargarMasProductos();
      }
    }
  }

  void _reiniciarLista() {
    _productos.clear();
    _paginaActual = 0;
    _hasMore = true;
    if (mounted) setState(() {});
  }

  Future<void> _cargarMasProductos() async {
    if (!mounted || _isLoading || !_hasMore) return;

    final currentFetchId = ++_fetchId;
    setState(() => _isLoading = true);

    try {
      final desde = _paginaActual * _tamanhoPagina;
      final hasta = desde + _tamanhoPagina - 1;

      var query = Supabase.instance.client.from('productos').select(
            'id, sku, upc, alu, descripcion_1, precio_venta, costo, inventario(stock)',
          );

      if (_searchQuery.isNotEmpty) {
        query = query.or(
          'descripcion_1.ilike.%$_searchQuery%,sku.ilike.%$_searchQuery%,upc.ilike.%$_searchQuery%,alu.ilike.%$_searchQuery%',
        );
      }

      if (_catFiltro != null) query = query.eq('categoria', _catFiltro!);
      if (_claseFiltro != null) query = query.eq('clase', _claseFiltro!);
      if (_subClaseFiltro != null) query = query.eq('sub_clase', _subClaseFiltro!);

      final List<dynamic> data = await query
          .order('descripcion_1')
          .range(desde, hasta);

      if (!mounted || currentFetchId != _fetchId) return;

      setState(() {
        _productos.addAll(List<Map<String, dynamic>>.from(data));
        _paginaActual++;
        _isLoading = false;
        if (data.length < _tamanhoPagina) _hasMore = false;
      });
    } catch (e) {
      if (mounted && currentFetchId == _fetchId) {
        setState(() => _isLoading = false);
        debugPrint("Error: $e");
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Gestión de Inventario"),
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isScanning ? _buildScanner() : _buildSearchBar(),
          ),
          FiltrosJerarquiaWidget(
            onFiltrosCambiados: (cat, clase, sub) {
              _catFiltro = cat;
              _claseFiltro = clase;
              _subClaseFiltro = sub;
              _reiniciarLista();
              if (_isLoading) {
                setState(() => _isLoading = false);
              }
              _cargarMasProductos();
            },
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
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _productos.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _productos.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(15),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            );
                          }

                          final prod = _productos[index];
                          final int stock = _stockTotalDesdeProducto(prod);

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getColorStock(stock),
                                radius: 18,
                                child: Text("$stock",
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                              title: Text(
                                prod['descripcion_1'] ?? 'Sin nombre',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Text(
                                '\$${prod['precio_venta']}',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_note,
                                    color: Colors.white54),
                                onPressed: () => _editarProducto(prod),
                              ),
                            ),
                          );
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
            _reiniciarLista();
            // Evitamos la barrera de _isLoading artificialmente si es un refresh nuevo:
            if (_isLoading) {
              setState(() => _isLoading = false);
            }
            _cargarMasProductos();
          },
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar producto...',
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
                    final String code = barcodes.first.rawValue ?? '';
                    setState(() {
                      _isScanning = false;
                      _searchController.text = code;
                      _searchQuery = code;
                    });
                    _reiniciarLista();
                    _cargarMasProductos();
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

  Color _getColorStock(int stock) {
    if (stock <= 0) return Colors.red;
    if (stock <= 5) return Colors.orange;
    return Colors.green;
  }

  int _stockTotalDesdeProducto(Map<String, dynamic> prod) {
    final inv = prod['inventario'];
    if (inv == null) return 0;
    if (inv is List) {
      var sum = 0;
      for (final row in inv) {
        if (row is Map) {
          final s = row['stock'];
          if (s is num) sum += s.round();
        }
      }
      return sum;
    }
    if (inv is Map) {
      final s = inv['stock'];
      if (s is num) return s.round();
    }
    return 0;
  }

  void _editarProducto(Map<String, dynamic> producto) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DetalleProductoPage(
          producto: producto,
          origen: DetalleProductoOrigen.inventario,
          contextoInventario: true,
        ),
      ),
    );
  }
}
