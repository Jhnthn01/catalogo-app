import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'package:catalogo_digital_app/features/catalog/detalle_producto_page.dart';
import 'package:catalogo_digital_app/features/inventory/nuevo_producto_page.dart';
import 'package:catalogo_digital_app/features/inventory/carga_masiva_page.dart';
import 'package:catalogo_digital_app/widgets/filtros_jerarquia.dart';

class TablaDetalladaInventarioScreen extends StatefulWidget {
  final VoidCallback? onRefreshPadre;
  const TablaDetalladaInventarioScreen({super.key, this.onRefreshPadre});

  @override
  State<TablaDetalladaInventarioScreen> createState() =>
      _TablaDetalladaInventarioScreenState();
}

class _TablaDetalladaInventarioScreenState
    extends State<TablaDetalladaInventarioScreen> {
  static final NumberFormat _monedaFmt =
      NumberFormat.currency(symbol: 'S/. ', decimalDigits: 2);

  final List<Map<String, dynamic>> _todosLosProductos = [];
  List<Map<String, dynamic>> _productosFiltrados = [];
  bool _isLoading = true;
  bool _isLoadingMas = false;
  bool _hasMore = true;
  String _searchQuery = '';
  int _totalProductosCount = 0;
  Timer? _debounceTimer;

  String? _catFiltro;
  String? _claseFiltro;
  String? _subClaseFiltro;

  int _rowsPerPage = 15;
  int _sortColumnIndex = 1; // Por defecto ordenar por Descripción
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Obtener count total exacto de la BD en milisegundos (<10ms)
      final countRes = await Supabase.instance.client
          .from('productos')
          .select('id')
          .count(CountOption.exact);
      
      if (mounted) {
        _totalProductosCount = countRes.count;
      }

      // 2. Consulta filtrada directamente en Supabase (PostgreSQL)
      var query = Supabase.instance.client
          .from('productos')
          .select(
            'id, sku, upc, alu, marca, categoria, clase, sub_clase, descripcion_1, precio_venta, costo, ultimo_costo, costo_medio, inventario(stock)',
          );

      final q = _searchQuery.trim();
      if (q.isNotEmpty) {
        final List<String> tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (tokens.isNotEmpty) {
          final List<String> orClauses = [];
          for (final token in tokens) {
            orClauses.add('descripcion_1.ilike.%$token%');
            orClauses.add('sku.ilike.%$token%');
            orClauses.add('marca.ilike.%$token%');
            orClauses.add('upc.ilike.%$token%');
            orClauses.add('alu.ilike.%$token%');
          }
          query = query.or(orClauses.join(','));
        }
      }

      if (_catFiltro != null) query = query.eq('categoria', _catFiltro!);
      if (_claseFiltro != null) query = query.eq('clase', _claseFiltro!);
      if (_subClaseFiltro != null) query = query.eq('sub_clase', _subClaseFiltro!);

      // Si no hay filtro, carga inicial instantánea (primeros 100).
      // Si el usuario busca, la consulta busca en TODOS los 7.4k+ items de Supabase (máx 500 resultados).
      final limit = q.isNotEmpty ? 499 : 99;
      final List<dynamic> data = await query
          .order('descripcion_1')
          .range(0, limit);

      if (!mounted) return;

      final lista = List<Map<String, dynamic>>.from(data);
      setState(() {
        _todosLosProductos.clear();
        _todosLosProductos.addAll(lista);
        _hasMore = data.length >= limit && q.isEmpty;
        _aplicarFiltros();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando inventario: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Carga bajo demanda los siguientes bloques de 100 productos cuando el usuario avanza de página
  Future<void> _cargarMasProductosHasta(int targetIndex) async {
    if (_isLoadingMas || !_hasMore || !mounted || _searchQuery.trim().isNotEmpty) return;
    final int offset = _todosLosProductos.length;
    if (targetIndex < offset - 20) return;

    _isLoadingMas = true;
    try {
      var query = Supabase.instance.client
          .from('productos')
          .select(
            'id, sku, upc, alu, marca, categoria, clase, sub_clase, descripcion_1, precio_venta, costo, ultimo_costo, costo_medio, inventario(stock)',
          );

      if (_catFiltro != null) query = query.eq('categoria', _catFiltro!);
      if (_claseFiltro != null) query = query.eq('clase', _claseFiltro!);
      if (_subClaseFiltro != null) query = query.eq('sub_clase', _subClaseFiltro!);

      const int limit = 100;
      final List<dynamic> data = await query
          .order('descripcion_1')
          .range(offset, offset + limit - 1);

      if (!mounted) return;

      if (data.isNotEmpty) {
        final lista = List<Map<String, dynamic>>.from(data);
        _todosLosProductos.addAll(lista);
        if (data.length < limit) {
          _hasMore = false;
        }
        _aplicarFiltros();
      } else {
        _hasMore = false;
      }
    } catch (e) {
      debugPrint("Error cargando más productos: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMas = false;
        });
      }
    }
  }

  void _aplicarFiltros() {
    final query = _searchQuery.trim().toLowerCase();

    _productosFiltrados = _todosLosProductos.where((p) {
      // Filtro de jerarquía
      if (_catFiltro != null && p['categoria'] != _catFiltro) return false;
      if (_claseFiltro != null && p['clase'] != _claseFiltro) return false;
      if (_subClaseFiltro != null && p['sub_clase'] != _subClaseFiltro) return false;

      // Buscador por SKU, Nombre (descripcion_1) o Marca
      if (query.isNotEmpty) {
        final sku = (p['sku'] ?? '').toString().toLowerCase();
        final nombre = (p['descripcion_1'] ?? '').toString().toLowerCase();
        final marca = (p['marca'] ?? '').toString().toLowerCase();
        final upc = (p['upc'] ?? '').toString().toLowerCase();
        final alu = (p['alu'] ?? '').toString().toLowerCase();

        return sku.contains(query) ||
            nombre.contains(query) ||
            marca.contains(query) ||
            upc.contains(query) ||
            alu.contains(query);
      }

      return true;
    }).toList();

    _ordenarLista();
  }

  void _ordenarLista() {
    _productosFiltrados.sort((a, b) {
      dynamic valA;
      dynamic valB;

      switch (_sortColumnIndex) {
        case 0: // SKU
          valA = (a['sku'] ?? '').toString().toLowerCase();
          valB = (b['sku'] ?? '').toString().toLowerCase();
          break;
        case 1: // Producto
          valA = (a['descripcion_1'] ?? '').toString().toLowerCase();
          valB = (b['descripcion_1'] ?? '').toString().toLowerCase();
          break;
        case 2: // Categoría
          valA = (a['categoria'] ?? '').toString().toLowerCase();
          valB = (b['categoria'] ?? '').toString().toLowerCase();
          break;
        case 3: // Stock Total
          valA = _calcularStockTotal(a);
          valB = _calcularStockTotal(b);
          break;
        case 4: // Último Costo
          valA = _obtenerUltimoCosto(a);
          valB = _obtenerUltimoCosto(b);
          break;
        case 5: // Costo Medio
          valA = _obtenerCostoMedio(a);
          valB = _obtenerCostoMedio(b);
          break;
        case 6: // Precio Venta
          valA = (a['precio_venta'] as num?)?.toDouble() ?? 0.0;
          valB = (b['precio_venta'] as num?)?.toDouble() ?? 0.0;
          break;
        case 7: // Valor del Stock
          valA = _calcularStockTotal(a) * _obtenerCostoMedio(a);
          valB = _calcularStockTotal(b) * _obtenerCostoMedio(b);
          break;
        case 8: // Margen (%)
          valA = _calcularMargen(a);
          valB = _calcularMargen(b);
          break;
        default:
          valA = (a['descripcion_1'] ?? '').toString().toLowerCase();
          valB = (b['descripcion_1'] ?? '').toString().toLowerCase();
      }

      int comparison = 0;
      if (valA is Comparable && valB is Comparable) {
        comparison = valA.compareTo(valB);
      }

      return _sortAscending ? comparison : -comparison;
    });
  }

  // ── Mapeo y Métodos Helper ────────────────────────────────────────────────
  int _calcularStockTotal(Map<String, dynamic> prod) {
    final inv = prod['inventario'];
    if (inv == null) return 0;
    if (inv is List) {
      int sum = 0;
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

  double _obtenerUltimoCosto(Map<String, dynamic> prod) {
    final uc = double.tryParse(prod['ultimo_costo']?.toString() ?? '');
    if (uc != null && uc > 0) {
      return uc;
    }
    final c = double.tryParse(prod['costo']?.toString() ?? '');
    if (c != null) {
      return c;
    }
    return 0.0;
  }

  double _obtenerCostoMedio(Map<String, dynamic> prod) {
    final cm = double.tryParse(prod['costo_medio']?.toString() ?? '');
    if (cm != null && cm > 0) {
      return cm;
    }
    final c = double.tryParse(prod['costo']?.toString() ?? '');
    if (c != null) {
      return c;
    }
    return 0.0;
  }

  double _calcularMargen(Map<String, dynamic> prod) {
    final precio = (prod['precio_venta'] as num?)?.toDouble() ?? 0.0;
    final costoMedio = _obtenerCostoMedio(prod);
    if (precio <= 0) return 0.0;
    return ((precio - costoMedio) / precio) * 100;
  }

  // ── Métricas KPI ──────────────────────────────────────────────────────────
  int get _totalProductosRegistrados =>
      _totalProductosCount > 0 ? _totalProductosCount : _todosLosProductos.length;

  double get _valorTotalInventario {
    double total = 0.0;
    for (final prod in _todosLosProductos) {
      final stock = _calcularStockTotal(prod);
      final costoMedio = _obtenerCostoMedio(prod);
      total += (stock * costoMedio);
    }
    return total;
  }

  int get _stockTotalGlobal {
    int total = 0;
    for (final prod in _todosLosProductos) {
      total += _calcularStockTotal(prod);
    }
    return total;
  }

  void _abrirFichaProducto(Map<String, dynamic> producto) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DetalleProductoPage(
          producto: producto,
          origen: DetalleProductoOrigen.inventario,
          contextoInventario: true,
        ),
      ),
    ).then((_) {
      _cargarProductos();
      if (widget.onRefreshPadre != null) widget.onRefreshPadre!();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          // ── Resumen KPI para Escritorio ──────────────────────────────────
          _buildTarjetasKpi(),

          // ── Barra de Búsqueda y Filtros ──────────────────────────────────
          _buildBarraBusquedaYAcciones(),

          // ── Filtros de Jerarquía ─────────────────────────────────────────
          FiltrosJerarquiaWidget(
            onFiltrosCambiados: (cat, clase, sub) {
              setState(() {
                _catFiltro = cat;
                _claseFiltro = clase;
                _subClaseFiltro = sub;
              });
              _cargarProductos();
            },
          ),

          // ── Tabla Principal ──────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent),
                  )
                : _productosFiltrados.isEmpty
                    ? const Center(
                        child: Text(
                          'No se encontraron productos que coincidan con la búsqueda.',
                          style: TextStyle(color: Colors.white54, fontSize: 15),
                        ),
                      )
                    : _buildTablaDetallada(),
          ),
        ],
      ),
    );
  }

  // ── Componente Tarjetas KPI ───────────────────────────────────────────────
  Widget _buildTarjetasKpi() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _buildKpiCard(
            titulo: 'Total Productos Registrados',
            valor: '$_totalProductosRegistrados',
            icono: Icons.inventory_2_outlined,
            color: Colors.blueAccent,
            subtitulo: '${_productosFiltrados.length} listados en vista',
          ),
          const SizedBox(width: 16),
          _buildKpiCard(
            titulo: 'Valor Total del Inventario',
            valor: _monedaFmt.format(_valorTotalInventario),
            icono: Icons.account_balance_wallet_outlined,
            color: Colors.greenAccent,
            subtitulo: 'Calculado a Costo Medio Variable (PMP)',
          ),
          const SizedBox(width: 16),
          _buildKpiCard(
            titulo: 'Stock Físico Global',
            valor: '$_stockTotalGlobal uds.',
            icono: Icons.widgets_outlined,
            color: Colors.tealAccent,
            subtitulo: 'Suma de unidades en todas las sucursales',
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String titulo,
    required String valor,
    required IconData icono,
    required Color color,
    required String subtitulo,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icono, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    valor,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Componente Buscador y Botones ─────────────────────────────────────────
  Widget _buildBarraBusquedaYAcciones() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                onChanged: (val) {
                  _debounceTimer?.cancel();
                  _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                    if (!mounted) return;
                    setState(() {
                      _searchQuery = val;
                    });
                    _cargarProductos();
                  });
                },
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Buscar por SKU, Nombre, Marca, UPC o ALU...',
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: Colors.blueAccent, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Recargar Datos',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF1E1E1E),
              padding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.white12),
              ),
            ),
            icon: const Icon(Icons.refresh, color: Colors.blueAccent, size: 20),
            onPressed: _cargarProductos,
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              side: const BorderSide(color: Colors.blueAccent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CargaMasivaPage(),
                ),
              ).then((val) {
                if (val == true) _cargarProductos();
              });
            },
            icon: const Icon(Icons.upload_file, color: Colors.blueAccent, size: 18),
            label: const Text(
              'Importar CSV',
              style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NuevoProductoPage(),
                ),
              ).then((val) {
                if (val == true) _cargarProductos();
              });
            },
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text(
              'Nuevo Producto',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── Componente DataTable ─────────────────────────────────────────────────
  Widget _buildTablaDetallada() {
    final dataSource = _InventarioDataTableSource(
      productos: _productosFiltrados,
      onEdit: _abrirFichaProducto,
      calcularStock: _calcularStockTotal,
      obtenerUltimoCosto: _obtenerUltimoCosto,
      obtenerCostoMedio: _obtenerCostoMedio,
      calcularMargen: _calcularMargen,
      monedaFmt: _monedaFmt,
      totalCount: _searchQuery.trim().isEmpty ? _totalProductosCount : _productosFiltrados.length,
      hasMore: _hasMore && _searchQuery.trim().isEmpty,
      onLoadMoreTarget: (targetIndex) => _cargarMasProductosHasta(targetIndex),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white10),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            cardColor: const Color(0xFF1E1E1E),
            dividerColor: Colors.white10,
            textTheme: Theme.of(context).textTheme.copyWith(
                  bodySmall: const TextStyle(color: Colors.white70),
                ),
          ),
          child: PaginatedDataTable(
            header: Row(
              children: [
                const Text(
                  'Maestro de Productos',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_productosFiltrados.length} registros',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            rowsPerPage: _rowsPerPage > 100 ? 100 : _rowsPerPage,
            availableRowsPerPage: const [10, 15, 25, 50, 100],
            onRowsPerPageChanged: (val) {
              if (val != null) {
                setState(() => _rowsPerPage = val);
              }
            },
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            showFirstLastButtons: true,
            columns: [
              DataColumn(
                label: const Text('SKU', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                label: const Text('Producto', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                label: const Text('Categoría', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                numeric: true,
                label: const Text('Stock Total', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                numeric: true,
                label: const Text('Último Costo', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                numeric: true,
                label: const Text('Costo Medio (PMP)', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                numeric: true,
                label: const Text('Precio Venta', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                numeric: true,
                label: const Text('Valor Stock', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              DataColumn(
                numeric: true,
                label: const Text('Margen %', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                onSort: (idx, asc) => _onSort(idx, asc),
              ),
              const DataColumn(
                label: Text('Acciones', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
              ),
            ],
            source: dataSource,
          ),
        ),
      ),
    );
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _ordenarLista();
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DataTable Source para PaginatedDataTable
// ─────────────────────────────────────────────────────────────────────────────
class _InventarioDataTableSource extends DataTableSource {
  final List<Map<String, dynamic>> productos;
  final Function(Map<String, dynamic>) onEdit;
  final int Function(Map<String, dynamic>) calcularStock;
  final double Function(Map<String, dynamic>) obtenerUltimoCosto;
  final double Function(Map<String, dynamic>) obtenerCostoMedio;
  final double Function(Map<String, dynamic>) calcularMargen;
  final NumberFormat monedaFmt;
  final int totalCount;
  final bool hasMore;
  final Function(int) onLoadMoreTarget;

  _InventarioDataTableSource({
    required this.productos,
    required this.onEdit,
    required this.calcularStock,
    required this.obtenerUltimoCosto,
    required this.obtenerCostoMedio,
    required this.calcularMargen,
    required this.monedaFmt,
    required this.totalCount,
    required this.hasMore,
    required this.onLoadMoreTarget,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= productos.length - 15 && hasMore) {
      onLoadMoreTarget(index);
    }
    if (index >= productos.length) {
      return DataRow.byIndex(
        index: index,
        cells: const [
          DataCell(Text('⏳ Cargando...', style: TextStyle(color: Colors.grey))),
          DataCell(Text('Obteniendo datos de página...', style: TextStyle(color: Colors.grey))),
          DataCell(Text('—', style: TextStyle(color: Colors.grey))),
          DataCell(Text('—', style: TextStyle(color: Colors.grey))),
          DataCell(Text('—', style: TextStyle(color: Colors.grey))),
          DataCell(Text('—', style: TextStyle(color: Colors.grey))),
          DataCell(Text('—', style: TextStyle(color: Colors.grey))),
          DataCell(Text('—', style: TextStyle(color: Colors.grey))),
          DataCell(Text('—', style: TextStyle(color: Colors.grey))),
          DataCell(SizedBox.shrink()),
        ],
      );
    }
    final prod = productos[index];

    final stockTotal = calcularStock(prod);
    final ultimoCosto = obtenerUltimoCosto(prod);
    final costoMedio = obtenerCostoMedio(prod);
    final precioVenta = (prod['precio_venta'] as num?)?.toDouble() ?? 0.0;
    final valorStock = stockTotal * costoMedio;
    final margen = calcularMargen(prod);

    final bool tieneBajoStock = stockTotal <= 0;

    return DataRow.byIndex(
      index: index,
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (tieneBajoStock) return Colors.orangeAccent.withOpacity(0.08);
        return index.isEven ? const Color(0xFF1A1A1A) : const Color(0xFF222222);
      }),
      cells: [
        // SKU
        DataCell(
          Text(
            prod['sku'] ?? '—',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        // Producto (descripcion_1)
        DataCell(
          SizedBox(
            width: 200,
            child: Text(
              prod['descripcion_1'] ?? 'Sin nombre',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Categoría
        DataCell(
          Text(
            prod['categoria'] ?? '—',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        // Stock Total
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tieneBajoStock
                  ? Colors.redAccent.withOpacity(0.2)
                  : Colors.greenAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: tieneBajoStock ? Colors.redAccent : Colors.greenAccent,
              ),
            ),
            child: Text(
              '$stockTotal',
              style: TextStyle(
                color: tieneBajoStock ? Colors.redAccent : Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        // Último Costo
        DataCell(
          Text(
            monedaFmt.format(ultimoCosto),
            style: const TextStyle(color: Colors.blueAccent, fontSize: 13),
          ),
        ),
        // Costo Medio Variable
        DataCell(
          Text(
            monedaFmt.format(costoMedio),
            style: const TextStyle(color: Colors.tealAccent, fontSize: 13),
          ),
        ),
        // Precio Venta
        DataCell(
          Text(
            monedaFmt.format(precioVenta),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        // Valor del Stock
        DataCell(
          Text(
            monedaFmt.format(valorStock),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        // Margen (%)
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: margen < 15
                  ? Colors.red.withOpacity(0.15)
                  : margen < 30
                      ? Colors.orange.withOpacity(0.15)
                      : Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${margen.toStringAsFixed(1)}%',
              style: TextStyle(
                color: margen < 15
                    ? Colors.redAccent
                    : margen < 30
                        ? Colors.orangeAccent
                        : Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        // Acciones
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.blueAccent),
            tooltip: 'Editar Ficha / Inventario',
            onPressed: () => onEdit(prod),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => productos.length + (hasMore ? 1 : 0);

  @override
  int get selectedRowCount => 0;
}
