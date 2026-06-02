import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:convert';

import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/features/inventory/nuevo_producto_page.dart';
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

  Future<void> _exportarCSV() async {
    final tiendas = TiendaService().tiendas;
    if (tiendas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay tiendas disponibles para exportar.')));
      return;
    }

    int? tiendaIdSeleccionada = tiendas.first['id'];

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Text("Seleccionar Tienda", style: TextStyle(color: Colors.white)),
              content: DropdownButton<int>(
                value: tiendaIdSeleccionada,
                dropdownColor: const Color(0xFF1E1E1E),
                isExpanded: true,
                items: tiendas.map((t) {
                  return DropdownMenuItem<int>(
                    value: t['id'] as int,
                    child: Text(t['nombre'] ?? '', style: const TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setStateDialog(() => tiendaIdSeleccionada = val);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("EXPORTAR", style: TextStyle(color: Colors.greenAccent)),
                ),
              ],
            );
          }
        );
      }
    );

    if (confirmar != true || tiendaIdSeleccionada == null) return;
    
    setState(() => _isLoading = true);
    try {
      List<dynamic> allRows = [];
      int offset = 0;
      const int limit = 1000;
      bool hasMore = true;

      while (hasMore) {
        final List<dynamic> response = await Supabase.instance.client
            .from('inventario')
            .select('stock, tiendas(nombre), productos(sku, upc, marca, categoria, clase, sub_clase, estilo, descripcion_1, color, costo, precio_venta)')
            .eq('tienda_id', tiendaIdSeleccionada!)
            .range(offset, offset + limit - 1);

        if (response.isEmpty) {
          hasMore = false;
        } else {
          allRows.addAll(response);
          if (response.length < limit) {
            hasMore = false;
          } else {
            offset += limit;
          }
        }
      }

      if (allRows.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay productos para esta tienda')));
        setState(() => _isLoading = false);
        return;
      }
      
      final String nombreTienda = allRows.first['tiendas']?['nombre'] ?? 'tienda';
      
      List<List<dynamic>> rows = [];
      rows.add(['SKU', 'UPC', 'Marca', 'Categoria', 'Clase', 'Subclase', 'Estilo', 'Descripcion', 'Color', 'Costo', 'Precio', 'Stock', 'Tienda']);
      
      for (var row in allRows) {
        final p = row['productos'] ?? {};
        rows.add([
          p['sku'] ?? '',
          p['upc'] ?? '',
          p['marca'] ?? '',
          p['categoria'] ?? '',
          p['clase'] ?? '',
          p['sub_clase'] ?? '',
          p['estilo'] ?? '',
          p['descripcion_1'] ?? '',
          p['color'] ?? '',
          p['costo'] ?? 0,
          p['precio_venta'] ?? 0,
          row['stock'] ?? 0,
          nombreTienda
        ]);
      }
      
      String csvData = csv.encode(rows);
      final bytes = utf8.encode(csvData);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = 'maestro_${nombreTienda.replaceAll(' ', '_')}.csv';
      html.document.body!.children.add(anchor);
      anchor.click();
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
      
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during export: ${e.message} - ${e.details}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de base de datos: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('GeneralException during export: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Inventario"),
        backgroundColor: Colors.transparent,
        actions: [
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download, color: Colors.greenAccent),
                  tooltip: 'Exportar Maestro CSV',
                  onPressed: _exportarCSV,
                )
        ],
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
                          final bool urgencia = stock <= 0;

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: urgencia
                                  ? const BorderSide(color: Colors.orangeAccent, width: 2)
                                  : BorderSide.none,
                            ),
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
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    'S/.${prod['precio_venta']}',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (urgencia)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orangeAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.orangeAccent),
                                      ),
                                      child: const Text("⚠️ STOCK EN 0 - REQUERE REGULARIZAR", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                ],
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NuevoProductoPage()),
          ).then((value) {
            if (value == true) {
              _reiniciarLista();
              _cargarMasProductos();
            }
          });
        },
        child: const Icon(Icons.add, color: Colors.white),
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
    ).then((_) {
      _reiniciarLista();
      _cargarMasProductos();
    });
  }
}
