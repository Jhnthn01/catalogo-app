import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/widgets/filtros_jerarquia.dart';
import 'package:catalogo_digital_app/widgets/buscador_productos_widget.dart';
import 'package:catalogo_digital_app/widgets/toma_progreso_card.dart';
import 'package:catalogo_digital_app/features/catalog/detalle_producto_page.dart';
import 'package:catalogo_digital_app/features/inventory/nuevo_producto_page.dart';

class ProductListWidget extends StatefulWidget {
  final VoidCallback onCerrarCatalogo;
  final Function(Map<String, dynamic> producto, int cantidad, int stockActual) onProductoAgregado;

  const ProductListWidget({
    super.key,
    required this.onCerrarCatalogo,
    required this.onProductoAgregado,
  });

  @override
  State<ProductListWidget> createState() => ProductListWidgetState();
}

class ProductListWidgetState extends State<ProductListWidget> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _productos = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String _searchQuery = "";
  String _modoBusqueda = 'cualquiera';
  Timer? _searchDebounce;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _hasMore = true;
  int _paginaActual = 0;
  final int _tamanhoPagina = 20;
  int _fetchId = 0;

  String? _catFiltro;
  String? _claseFiltro;
  String? _subClaseFiltro;

  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _fetchProductos(refresh: true);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _searchController.dispose();
    _scannerController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
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

  void refrescar() {
    if (mounted) {
      _fetchProductos(refresh: true);
    }
  }

  Future<void> _fetchProductos({bool refresh = false, String? scannedSku}) async {
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

      final tiendaId = TiendaService().tiendaActivaId.value;
      final rol = TiendaService().usuarioRol?.toLowerCase() ?? 'cliente';
      final bool esOperativo = !(rol == 'admin' || rol == 'administrador' || rol == 'gerente');

      final fields = 'id, sku, upc, alu, marca, categoria, clase, sub_clase, estilo, descripcion_1, descripcion_2, color, costo, precio_venta, ultimo_costo, fecha_ultimo_costo, costo_medio';
      final invSelect = (tiendaId != null || esOperativo)
          ? '$fields, inventario!inner(stock, tienda_id)'
          : '$fields, inventario(stock, tienda_id)';

      var query = _supabase.from('productos').select(invSelect);

      if (tiendaId != null) {
        query = query.eq('inventario.tienda_id', tiendaId);
      } else if (esOperativo) {
        query = query.eq('inventario.tienda_id', -1);
      }

      if (_catFiltro != null) query = query.eq('categoria', _catFiltro!);
      if (_claseFiltro != null) query = query.eq('clase', _claseFiltro!);
      if (_subClaseFiltro != null) query = query.eq('sub_clase', _subClaseFiltro!);

      final q = _searchQuery.trim();
      final List<String> tokens = q.isEmpty
          ? []
          : (q.contains('%')
              ? q.split('%').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
              : [q]);

      if (tokens.isNotEmpty) {
        final params = <String, dynamic>{
          'p_tokens': tokens,
          'p_tienda_id': tiendaId,
          'p_categoria': _catFiltro,
          'p_clase': _claseFiltro,
          'p_sub_clase': _subClaseFiltro,
          'p_limit': 500,
          'p_offset': 0,
          'p_modo': _modoBusqueda,
        };

        final List<dynamic> data = await _supabase.rpc(
          'buscar_productos',
          params: params,
        );

        final list = List<dynamic>.from(data);

        if (_modoBusqueda == 'cualquiera' && tokens.length > 1) {
          int firstMatchIndex(dynamic prod) {
            final desc1 = (prod['descripcion_1'] ?? '').toString().toLowerCase();
            final sku = (prod['sku'] ?? '').toString().toLowerCase();
            final upc = (prod['upc'] ?? '').toString().toLowerCase();
            final marca = (prod['marca'] ?? '').toString().toLowerCase();
            final alu = (prod['alu'] ?? '').toString().toLowerCase();

            for (int i = 0; i < tokens.length; i++) {
              final t = tokens[i].toLowerCase();
              if (desc1.contains(t) ||
                  sku.contains(t) ||
                  upc.contains(t) ||
                  marca.contains(t) ||
                  alu.contains(t)) {
                return i;
              }
            }
            return tokens.length;
          }

          list.sort((a, b) {
            final idxA = firstMatchIndex(a);
            final idxB = firstMatchIndex(b);
            if (idxA != idxB) return idxA.compareTo(idxB);
            final nomA = (a['descripcion_1'] ?? '').toString().toLowerCase();
            final nomB = (b['descripcion_1'] ?? '').toString().toLowerCase();
            return nomA.compareTo(nomB);
          });
        }

        if (!mounted || currentFetchId != _fetchId) return;

        setState(() {
          _productos = list;
          _hasMore = false;
          _isLoading = false;
        });

        if (scannedSku != null && scannedSku.isNotEmpty && list.isEmpty) {
          _mostrarDialogoCrearProducto(scannedSku);
        }
      } else {
        final data = await query.order('descripcion_1', ascending: true).range(desde, hasta);

        if (!mounted || currentFetchId != _fetchId) return;

        setState(() {
          _productos.addAll(data);
          _paginaActual++;
          _isLoading = false;
          if (data.length < _tamanhoPagina) _hasMore = false;
        });

        if (scannedSku != null && scannedSku.isNotEmpty && _productos.isEmpty) {
          _mostrarDialogoCrearProducto(scannedSku);
        }
      }
    } catch (e) {
      if (mounted && currentFetchId == _fetchId) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _mostrarDialogoCrearProducto(String skuEscaneado) async {
    if (!mounted) return;
    final bool? deseaCrear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.blueAccent, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Producto no encontrado',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            children: [
              const TextSpan(text: 'No se encontró ningún producto con el código SKU:\n\n'),
              TextSpan(
                text: '🏷️ $skuEscaneado\n\n',
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const TextSpan(text: '¿Deseas registrar este nuevo producto ahora?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crear Producto', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (deseaCrear == true && mounted) {
      final bool? creado = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => NuevoProductoPage(initialSku: skuEscaneado),
        ),
      );

      if (creado == true && mounted) {
        _searchController.text = skuEscaneado;
        _searchQuery = skuEscaneado;
        _fetchProductos(refresh: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Punto de Ventas",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen_exit, color: Colors.redAccent),
            onPressed: widget.onCerrarCatalogo,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Active Toma de Inventario banner if in progress
                const SliverToBoxAdapter(
                  child: TomaProgresoCard(margin: EdgeInsets.fromLTRB(16, 12, 16, 4)),
                ),

                // Search bar or scanner
                SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isScanning
                        ? _buildScanner()
                        : BuscadorProductosWidget(
                            controller: _searchController,
                            modoBusqueda: _modoBusqueda,
                            onQueryChanged: (val) {
                              _searchQuery = val.trim();
                              _searchDebounce?.cancel();
                              _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                                if (mounted) _fetchProductos(refresh: true);
                              });
                            },
                            onModoChanged: (nuevoModo) {
                              setState(() {
                                _modoBusqueda = nuevoModo;
                              });
                              _fetchProductos(refresh: true);
                            },
                            onScanPressed: () => setState(() => _isScanning = true),
                          ),
                  ),
                ),

                // Hierarchy filters
                SliverToBoxAdapter(
                  child: FiltrosJerarquiaWidget(
                    onFiltrosCambiados: (cat, clase, sub) {
                      _catFiltro = cat;
                      _claseFiltro = clase;
                      _subClaseFiltro = sub;
                      _fetchProductos(refresh: true);
                    },
                  ),
                ),

                // Product list (virtualized)
                ..._buildProductSliver(),

                // Bottom spacing
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildProductSliver() {
    if (_productos.isEmpty && _isLoading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_productos.isEmpty && !_isLoading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Center(
              child: Text(
                'No se encontraron productos.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ),
      ];
    }

    final int itemCount = _productos.length + (_hasMore ? 1 : 0);

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == _productos.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return _buildProductCard(_productos[index]);
            },
            childCount: itemCount,
          ),
        ),
      ),
    ];
  }

  Widget _buildScanner() {
    return Padding(
      key: const ValueKey(2),
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueAccent, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    final String code = (barcodes.first.rawValue ?? "").trim();
                    if (code.isNotEmpty) {
                      setState(() {
                        _isScanning = false;
                        _searchController.text = code;
                        _searchQuery = code;
                      });
                      _fetchProductos(refresh: true, scannedSku: code);
                    }
                  }
                },
              ),
              Positioned(
                left: 10,
                top: 10,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _scannerController,
                    builder: (context, state, child) {
                      switch (state.torchState) {
                        case TorchState.off:
                          return IconButton(
                            icon: const Icon(Icons.flash_off, color: Colors.white),
                            onPressed: () => _scannerController.toggleTorch(),
                          );
                        case TorchState.on:
                          return IconButton(
                            icon: const Icon(Icons.flash_on, color: Colors.yellow),
                            onPressed: () => _scannerController.toggleTorch(),
                          );
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
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

    final String skuTexto = producto['sku'] ?? producto['upc'] ?? 'Sin código';

    return Card(
      color: const Color(0xFF1E1E1E),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _mostrarOpcionesProducto(producto, totalStock),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto['descripcion_1'] ?? 'Sin nombre',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "SKU: $skuTexto",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "S/.${producto['precio_venta'] ?? '0.00'}",
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Stock: $totalStock",
                        style: TextStyle(
                          color: totalStock > 0 ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _mostrarDisponibilidadTiendas(producto),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Icon(
                            Icons.store_mall_directory_rounded,
                            color: totalStock == 0 ? Colors.orangeAccent : Colors.blueAccent,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    widget.onProductoAgregado(producto, 1, totalStock);
                    _mostrarAlertaRetorno(producto['descripcion_1'] ?? 'Producto');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.add_shopping_cart_rounded, color: Colors.blueAccent, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarOpcionesProducto(Map<String, dynamic> producto, int totalStock) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            producto['descripcion_1'] ?? 'Opciones de Producto',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "¿Desea ver el detalle de este producto o añadirlo directamente al pedido?",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DetalleProductoPage(producto: producto),
                  ),
                ).then((_) {
                  _fetchProductos(refresh: true);
                });
              },
              child: const Text('VER DETALLE', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _solicitarCantidadYAnadir(producto, totalStock);
              },
              child: const Text('AÑADIR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _solicitarCantidadYAnadir(Map<String, dynamic> producto, int totalStock) async {
    final ctrl = TextEditingController(text: "1");
    final int? cantidad = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Ingresar Cantidad',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blueAccent),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blueAccent, width: 2),
            ),
          ),
          onTap: () => ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              final n = int.tryParse(ctrl.text);
              Navigator.pop(ctx, n);
            },
            child: const Text('ACEPTAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (cantidad != null && cantidad > 0) {
      widget.onProductoAgregado(producto, cantidad, totalStock);
      _mostrarAlertaRetorno(producto['descripcion_1'] ?? 'Producto');
    }
  }

  void _mostrarAlertaRetorno(String nombreProducto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "Producto añadido. ¿Deseas regresar a la pantalla de venta o seguir agregando?",
          style: TextStyle(fontSize: 13),
        ),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: "REGRESAR",
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).clearSnackBars();
            widget.onCerrarCatalogo();
          },
        ),
      ),
    );
  }

  Future<void> _mostrarDisponibilidadTiendas(Map<String, dynamic> producto) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.store_mall_directory_rounded, color: Colors.blueAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  producto['descripcion_1'] ?? 'Disponibilidad',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: FutureBuilder<List<dynamic>>(
            future: _supabase
                .from('inventario')
                .select('stock, tiendas(nombre)')
                .eq('producto_id', producto['id']),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 100,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent),
                  ),
                );
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 100,
                  child: Center(
                    child: Text(
                      "Error al cargar stock: ${snapshot.error}",
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                );
              }

              final List<dynamic> inventarios = snapshot.data ?? [];
              if (inventarios.isEmpty) {
                return const SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      "No hay stock registrado en otras tiendas.",
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                );
              }

              return Container(
                constraints: const BoxConstraints(maxHeight: 250),
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: inventarios.length,
                  itemBuilder: (context, index) {
                    final item = inventarios[index];
                    final tienda = item['tiendas'];
                    final String tiendaNombre = (tienda != null && tienda['nombre'] != null)
                        ? tienda['nombre'] as String
                        : 'Tienda desconocida';
                    final int stock = (item['stock'] as num?)?.toInt() ?? 0;
                    final bool hasStock = stock > 0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              tiendaNombre,
                              style: TextStyle(
                                color: hasStock ? Colors.white : Colors.white38,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            "$stock",
                            style: TextStyle(
                              color: hasStock ? Colors.greenAccent : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CERRAR', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
