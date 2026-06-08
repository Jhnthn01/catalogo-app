import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/app.dart';
import 'package:catalogo_digital_app/features/catalog/detalle_producto_page.dart';
import 'package:catalogo_digital_app/features/auth/sin_tienda_page.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';
import 'package:catalogo_digital_app/widgets/filtros_jerarquia.dart';

class CatalogoPage extends StatefulWidget {
  const CatalogoPage({super.key});

  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> with RouteAware {
  final _supabase = Supabase.instance.client;
  List<dynamic> _productos = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String _searchQuery = "";
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _hasMore = true;
  int _paginaActual = 0;
  final int _tamanhoPagina = 20;
  int _fetchId = 0;

  String? _catFiltro;
  String? _claseFiltro;
  String? _subClaseFiltro;
  String? _userRol;

  final MobileScannerController _scannerController = MobileScannerController();

  // Sales Module variables
  bool _isEntrega = false;
  bool _mostrarCatalogo = true;

  // Customer fields
  final TextEditingController _nombreClienteController = TextEditingController();
  final TextEditingController _telefonoClienteController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();
  final TextEditingController _fechaHoraController = TextEditingController();
  final TextEditingController _tipoDocumentoController = TextEditingController(text: 'DNI');
  final TextEditingController _numeroDocumentoController = TextEditingController();
  final TextEditingController _tipoComprobanteController = TextEditingController(text: 'Nota de Venta');
  final TextEditingController _formaPagoController = TextEditingController(text: 'Efectivo');
  final TextEditingController _segundoRecogeController = TextEditingController();
  DateTime? _fechaEntrega;
  TimeOfDay? _horaEntrega;

  // Payment mode
  bool _isPagoCombinado = false;
  final List<Map<String, dynamic>> _pagosCombinados = [
    {'metodo': 'Efectivo', 'montoController': TextEditingController()},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inicializarCatalogo();
    });
    _scrollController.addListener(_scrollListener);
    TiendaService().tiendaSeleccionadaId.addListener(_onTiendaChanged);
  }

  Future<void> _inicializarCatalogo() async {
    setState(() => _isLoading = true);
    await TiendaService().cargarTiendas();
    if (mounted) {
      setState(() {
        _userRol = TiendaService().usuarioRol ?? 'cliente';
      });
      _fetchProductos(refresh: true);
    }
  }

  void _onTiendaChanged() {
    if (mounted) _fetchProductos(refresh: true);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      routeObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void didPopNext() {
    _fetchProductos(refresh: true);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    TiendaService().tiendaSeleccionadaId.removeListener(_onTiendaChanged);
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _searchController.dispose();
    _scannerController.dispose();
    _nombreClienteController.dispose();
    _telefonoClienteController.dispose();
    _direccionController.dispose();
    _fechaHoraController.dispose();
    _tipoDocumentoController.dispose();
    _numeroDocumentoController.dispose();
    _tipoComprobanteController.dispose();
    _formaPagoController.dispose();
    _segundoRecogeController.dispose();
    for (var p in _pagosCombinados) {
      (p['montoController'] as TextEditingController).dispose();
    }
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

      final tiendaId = TiendaService().tiendaActivaId.value;
      final rol = _userRol?.toLowerCase() ?? 'cliente';
      final bool esOperativo = !(rol == 'admin' || rol == 'administrador' || rol == 'gerente');

      final fields = 'id, sku, upc, alu, marca, descripcion_1, descripcion_2, precio_venta, categoria, clase, sub_clase';
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

      final List<dynamic> data;
      if (_searchQuery.trim().isNotEmpty) {
        final term = _searchQuery.trim();
        final List<String> tokens = term.split(RegExp(r'\s+'));
        final List<String> orClauses = [];
        for (var token in tokens) {
          if (token.isNotEmpty) {
            orClauses.add('descripcion_1.ilike.%$token%');
            orClauses.add('descripcion_2.ilike.%$token%');
            orClauses.add('sku.ilike.%$token%');
            orClauses.add('upc.ilike.%$token%');
            orClauses.add('marca.ilike.%$token%');
            orClauses.add('alu.ilike.%$token%');
          }
        }
        if (orClauses.isNotEmpty) {
          query = query.or(orClauses.join(','));
        }
        data = await query.order('descripcion_1', ascending: true).limit(1000);
      } else {
        data = await query.order('descripcion_1', ascending: true).range(desde, hasta);
      }

      if (!mounted || currentFetchId != _fetchId) return;

      if (_searchQuery.trim().isNotEmpty) {
        final List<String> palabras = _searchQuery.toLowerCase().trim().split(RegExp(r'\s+'));
        final filtered = data.where((prod) {
          final skuLower = (prod['sku'] ?? '').toString().toLowerCase().trim();
          final upcLower = (prod['upc'] ?? '').toString().toLowerCase();
          final desc1 = (prod['descripcion_1'] ?? '').toString().toLowerCase();
          final desc2 = (prod['descripcion_2'] ?? '').toString().toLowerCase();
          final marca = (prod['marca'] ?? '').toString().toLowerCase();
          final alu = (prod['alu'] ?? '').toString().toLowerCase();
          final cat = (prod['categoria'] ?? '').toString().toLowerCase();
          final cla = (prod['clase'] ?? '').toString().toLowerCase();
          final sub = (prod['sub_clase'] ?? '').toString().toLowerCase();

          return palabras.every((palabraIngresada) {
            final String pi = palabraIngresada;
            return skuLower == pi ||
                skuLower.contains(pi) ||
                upcLower.contains(pi) ||
                desc1.contains(pi) ||
                marca.contains(pi) ||
                desc2.contains(pi) ||
                alu.contains(pi) ||
                cat.contains(pi) ||
                cla.contains(pi) ||
                sub.contains(pi);
          });
        }).toList();

        setState(() {
          _productos = filtered;
          _hasMore = false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _productos.addAll(data);
          _paginaActual++;
          _isLoading = false;
          if (data.length < _tamanhoPagina) _hasMore = false;
        });
      }
    } catch (e) {
      if (mounted && currentFetchId == _fetchId) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (TiendaService().sinTiendaAsignada) {
      return const SinTiendaPage();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      drawer: const MenuLateral(),
      appBar: AppBar(
        title: const Text(
          "Módulo de Ventas",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Header section
                SliverToBoxAdapter(child: _buildHeader()),

                // Customer fields
                SliverToBoxAdapter(child: _buildCustomerFields()),

                // Search bar or scanner
                SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isScanning ? _buildScanner() : _buildSearchBar(),
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

                // Catalog header toggle
                SliverToBoxAdapter(child: _buildCatalogHeader()),

                // Product list (virtualized)
                if (_mostrarCatalogo)
                  ..._buildProductSliver(),

                // Added products section
                SliverToBoxAdapter(child: _buildAddedProductsSection()),

                // Bottom spacing
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          ),
          _buildConfirmationFooter(),
        ],
      ),
    );
  }

  // ─── Catalog Header ────────────────────────────────────────────────────────
  Widget _buildCatalogHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Catálogo de Productos",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _mostrarCatalogo = !_mostrarCatalogo;
              });
            },
            icon: Icon(
              _mostrarCatalogo ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.blueAccent,
              size: 20,
            ),
            label: Text(
              _mostrarCatalogo ? "Ocultar" : "Mostrar",
              style: const TextStyle(color: Colors.blueAccent, fontSize: 13),
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

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isEntrega = !_isEntrega;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSwitchOption("En Tienda", !_isEntrega),
                          _buildSwitchOption("Entrega", _isEntrega),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Store selector — interactive for admin/manager, static otherwise
              _buildStoreBadge(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _isEntrega ? "Venta por Entrega" : "Venta en Tienda",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreBadge() {
    final rol = (_userRol ?? '').toLowerCase();
    final bool esAdminOGerente = rol == 'admin' || rol == 'administrador' || rol == 'gerente';

    return ValueListenableBuilder<int?>(
      valueListenable: TiendaService().tiendaActivaId,
      builder: (context, tiendaId, child) {
        final tiendaNombre = TiendaService().tiendas.firstWhere(
          (t) => t['id'] == tiendaId,
          orElse: () => {'nombre': 'Sin Tienda'},
        )['nombre'] as String;

        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: esAdminOGerente
                  ? Colors.blueAccent.withValues(alpha: 0.5)
                  : Colors.blueAccent.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.store_rounded, color: Colors.blueAccent, size: 16),
              const SizedBox(width: 4),
              Text(
                tiendaNombre,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              if (esAdminOGerente) ...[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.blueAccent, size: 16),
              ],
            ],
          ),
        );

        if (!esAdminOGerente) return badge;

        return PopupMenuButton<int>(
          onSelected: (int id) {
            TiendaService().seleccionarTienda(id);
          },
          color: const Color(0xFF2C2C2C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (context) {
            return TiendaService().tiendas.map((t) {
              return PopupMenuItem<int>(
                value: t['id'] as int,
                child: Row(
                  children: [
                    Icon(
                      t['id'] == tiendaId ? Icons.check : Icons.store_outlined,
                      color: t['id'] == tiendaId ? Colors.blueAccent : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t['nombre'] as String,
                      style: TextStyle(
                        color: t['id'] == tiendaId ? Colors.blueAccent : Colors.white,
                        fontWeight: t['id'] == tiendaId ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: badge,
        );
      },
    );
  }

  Widget _buildSwitchOption(String title, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.blueAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: active ? Colors.white : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  // ─── Customer Fields ────────────────────────────────────────────────────────
  Widget _buildCustomerFields() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Name & Phone (always shown)
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _nombreClienteController,
                  label: "Nombre del Cliente *",
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _telefonoClienteController,
                  label: "Teléfono *",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                ),
              ),
            ],
          ),

          // Delivery-only fields
          if (_isEntrega) ...[
            const SizedBox(height: 12),
            _buildTextField(
              controller: _direccionController,
              label: "Dirección de Entrega *",
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 12),
            // Document type & number
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildDropdownField(
                    controller: _tipoDocumentoController,
                    label: "Tipo Doc.",
                    icon: Icons.badge_outlined,
                    options: ['DNI', 'RUC', 'CE'],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    controller: _numeroDocumentoController,
                    label: "Número de Documento *",
                    icon: Icons.numbers_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDropdownField(
              controller: _tipoComprobanteController,
              label: "Tipo de Comprobante",
              icon: Icons.receipt_long_outlined,
              options: ['Nota de Venta', 'Boleta', 'Factura'],
            ),
            const SizedBox(height: 12),
            // Payment mode toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Forma de Pago",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('Único', style: TextStyle(fontSize: 12))),
                    ButtonSegment<bool>(value: true, label: Text('Combinado', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {_isPagoCombinado},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _isPagoCombinado = newSelection.first;
                    });
                  },
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: Colors.blueAccent.withValues(alpha: 0.3),
                    foregroundColor: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_isPagoCombinado)
              _buildDropdownField(
                controller: _formaPagoController,
                label: "Método de Pago",
                icon: Icons.payments_outlined,
                options: ['Efectivo', 'Tarjeta de Crédito/Débito', 'Yape', 'Plin', 'Transferencia Bancaria'],
              )
            else
              _buildPagoCombinado(),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _segundoRecogeController,
              label: "Segundo a Recoger (Opcional)",
              icon: Icons.people_outline,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _seleccionarFechaHora,
              child: AbsorbPointer(
                child: _buildTextField(
                  controller: _fechaHoraController,
                  label: "Fecha/Hora de Entrega *",
                  icon: Icons.calendar_month_outlined,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 18),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required List<String> options,
  }) {
    return DropdownButtonFormField<String>(
      value: options.contains(controller.text) ? controller.text : options.first,
      dropdownColor: const Color(0xFF2C2C2C),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 18),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
      ),
      items: options.map((opt) {
        return DropdownMenuItem(value: opt, child: Text(opt));
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          controller.text = val;
          setState(() {});
        }
      },
    );
  }

  Widget _buildPagoCombinado() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          ..._pagosCombinados.asMap().entries.map((entry) {
            final index = entry.key;
            final pago = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: pago['metodo'],
                      dropdownColor: const Color(0xFF2C2C2C),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2C2C2C),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: ['Efectivo', 'Tarjeta de Crédito/Débito', 'Yape', 'Plin', 'Transferencia Bancaria']
                          .map((opt) => DropdownMenuItem(
                                value: opt,
                                child: Text(opt, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _pagosCombinados[index]['metodo'] = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: pago['montoController'] as TextEditingController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Monto S/.",
                        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF2C2C2C),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  if (_pagosCombinados.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          (pago['montoController'] as TextEditingController).dispose();
                          _pagosCombinados.removeAt(index);
                        });
                      },
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.add, color: Colors.blueAccent),
            label: const Text("Añadir Método", style: TextStyle(color: Colors.blueAccent)),
            onPressed: () {
              setState(() {
                _pagosCombinados.add({
                  'metodo': 'Efectivo',
                  'montoController': TextEditingController(),
                });
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarFechaHora() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _fechaEntrega ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
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
      if (!mounted) return;
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: _horaEntrega ?? TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.blueAccent,
                onPrimary: Colors.white,
                surface: Color(0xFF1E1E1E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (time != null) {
        setState(() {
          _fechaEntrega = date;
          _horaEntrega = time;
          _fechaHoraController.text =
              "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${time.format(context)}";
        });
      }
    }
  }

  // ─── Search Bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      key: const ValueKey(1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white10),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim();
            });
            _fetchProductos(refresh: true);
          },
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Buscar producto...",
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
            suffixIcon: _searchController.text.isEmpty
                ? IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                    onPressed: () => setState(() => _isScanning = true),
                  )
                : IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = "";
                      });
                      FocusScope.of(context).unfocus();
                      _fetchProductos(refresh: true);
                    },
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

  // ─── Product Card ────────────────────────────────────────────────────────────
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
          ).then((_) {
            _fetchProductos(refresh: true);
          });
        },
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
                      "UPC: $upcTexto",
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
                  Text(
                    "Stock: $totalStock",
                    style: TextStyle(
                      color: totalStock > 0 ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    CartService().agregarProducto(producto, 1, stockActual: totalStock);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Añadido: ${producto['descripcion_1']}"),
                        backgroundColor: Colors.blueAccent,
                        duration: const Duration(milliseconds: 800),
                      ),
                    );
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

  // ─── Added Products Section ──────────────────────────────────────────────────
  Widget _buildCircularButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _buildAddedProductsSection() {
    return ValueListenableBuilder<int>(
      valueListenable: CartService().itemsCountNotifier,
      builder: (context, count, child) {
        final items = CartService().items;
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                "Productos en el Pedido",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                _buildCircularButton(
                                  icon: Icons.remove,
                                  color: Colors.white70,
                                  onTap: () {
                                    CartService().actualizarCantidad(item.id, item.cantidad - 1);
                                    setState(() {});
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    '${item.cantidad}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _buildCircularButton(
                                  icon: Icons.add,
                                  color: Colors.blueAccent,
                                  onTap: () {
                                    CartService().actualizarCantidad(item.id, item.cantidad + 1);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "P.U. S/.${item.precio.toStringAsFixed(2)}",
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                ),
                                Text(
                                  "P.T. S/.${(item.precio * item.cantidad).toStringAsFixed(2)}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                              onPressed: () {
                                CartService().eliminarProducto(item.id);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ─── Confirmation Footer ─────────────────────────────────────────────────────
  Widget _buildConfirmationFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Total Estimado:",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: CartService().itemsCountNotifier,
                  builder: (context, count, child) {
                    return Text(
                      "S/.${CartService().total.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
              ),
              onPressed: _isLoading ? null : _confirmarPedido,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "CONFIRMAR MI PEDIDO",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Confirm Order ───────────────────────────────────────────────────────────
  Future<void> _confirmarPedido() async {
    final nombre = _nombreClienteController.text.trim();
    final telefono = _telefonoClienteController.text.trim();
    final items = CartService().items;

    if (nombre.isEmpty) {
      _showError("Por favor, ingresa el nombre del cliente.");
      return;
    }
    if (telefono.isEmpty) {
      _showError("Por favor, ingresa el teléfono del cliente.");
      return;
    }
    if (telefono.length != 9) {
      _showError("El teléfono debe tener exactamente 9 dígitos.");
      return;
    }

    String formaPagoFinal = '';

    if (_isEntrega) {
      if (_direccionController.text.trim().isEmpty) {
        _showError("Por favor, ingresa la dirección de entrega.");
        return;
      }
      final numDoc = _numeroDocumentoController.text.trim();
      if (numDoc.isEmpty) {
        _showError("Por favor, ingresa el número de documento.");
        return;
      }
      if (_fechaEntrega == null) {
        _showError("Por favor, selecciona la fecha y hora de entrega.");
        return;
      }

      if (_isPagoCombinado) {
        double suma = 0;
        List<String> partes = [];
        for (var p in _pagosCombinados) {
          final ctrl = p['montoController'] as TextEditingController;
          final monto = double.tryParse(ctrl.text.trim()) ?? 0.0;
          suma += monto;
          partes.add("${p['metodo']}: S/.${monto.toStringAsFixed(2)}");
        }
        if (suma.toStringAsFixed(2) != CartService().total.toStringAsFixed(2)) {
          _showError("La suma de los pagos (S/.${suma.toStringAsFixed(2)}) debe coincidir con el total del pedido (S/.${CartService().total.toStringAsFixed(2)}).");
          return;
        }
        formaPagoFinal = partes.join(" | ");
      } else {
        formaPagoFinal = _formaPagoController.text.trim();
      }
    } else {
      // In-store: use default values
      formaPagoFinal = 'Efectivo';
    }

    if (items.isEmpty) {
      _showError("Por favor, añade al menos un producto al pedido.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("Sesión inválida.");

      bool requiereRegularizacion = false;
      for (var item in items) {
        if (item.cantidad > item.stockActual) {
          requiereRegularizacion = true;
          break;
        }
      }

      DateTime fechaEntregaFinal = DateTime.now();
      if (_isEntrega && _fechaEntrega != null && _horaEntrega != null) {
        fechaEntregaFinal = DateTime(
          _fechaEntrega!.year,
          _fechaEntrega!.month,
          _fechaEntrega!.day,
          _horaEntrega!.hour,
          _horaEntrega!.minute,
        );
      }

      final pedido = await _supabase.from('pedidos').insert({
        'usuario_id': user.id,
        'total': CartService().total,
        'estado': 'pendiente',
        'nombre_cliente': nombre,
        'telefono_cliente': telefono,
        'direccion_cliente': _isEntrega ? _direccionController.text.trim() : null,
        'tipo_documento': _isEntrega ? _tipoDocumentoController.text.trim() : null,
        'numero_documento': _isEntrega ? _numeroDocumentoController.text.trim() : null,
        'tipo_comprobante': _isEntrega ? _tipoComprobanteController.text.trim() : 'Nota de Venta',
        'forma_pago': formaPagoFinal,
        'segundo_recoge': _isEntrega && _segundoRecogeController.text.trim().isNotEmpty
            ? _segundoRecogeController.text.trim()
            : null,
        'fecha_entrega': fechaEntregaFinal.toIso8601String(),
        'requiere_regularizacion': requiereRegularizacion,
        'tienda_id': TiendaService().tiendaActivaId.value,
      }).select().single();

      final detalles = items
          .map((item) => {
                'pedido_id': pedido['id'],
                'producto_id': item.id,
                'cantidad': item.cantidad,
                'precio_unitario': item.precio,
              })
          .toList();

      await _supabase.from('detalles_pedido').insert(detalles);

      CartService().limpiar();
      _limpiarFormulario();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("¡Pedido registrado con éxito!", style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al registrar pedido: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _fetchProductos(refresh: true);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _limpiarFormulario() {
    _nombreClienteController.clear();
    _telefonoClienteController.clear();
    _direccionController.clear();
    _fechaHoraController.clear();
    _numeroDocumentoController.clear();
    _segundoRecogeController.clear();
    _tipoDocumentoController.text = 'DNI';
    _tipoComprobanteController.text = 'Nota de Venta';
    _formaPagoController.text = 'Efectivo';
    _fechaEntrega = null;
    _horaEntrega = null;
    _isPagoCombinado = false;
    // Dispose and reset combined payments
    for (var p in _pagosCombinados) {
      (p['montoController'] as TextEditingController).dispose();
    }
    _pagosCombinados
      ..clear()
      ..add({'metodo': 'Efectivo', 'montoController': TextEditingController()});
    setState(() {});
  }
}
