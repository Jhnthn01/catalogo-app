import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:catalogo_digital_app/features/inventory/nuevo_producto_page.dart';
import 'package:catalogo_digital_app/features/inventory/revision_toma_page.dart';
import 'package:catalogo_digital_app/widgets/buscador_productos_widget.dart';
import 'package:catalogo_digital_app/services/toma_inventario_service.dart';

class ConteoTomaPage extends StatefulWidget {
  final String tomaId;

  const ConteoTomaPage({super.key, required this.tomaId});

  @override
  State<ConteoTomaPage> createState() => _ConteoTomaPageState();
}

class _ConteoTomaPageState extends State<ConteoTomaPage> {
  final _supabase = Supabase.instance.client;

  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cantidadController = TextEditingController(text: '1');
  final FocusNode _cantidadFocusNode = FocusNode();

  String _modoBusqueda = 'cualquiera'; // 'todas' | 'cualquiera'
  Timer? _searchDebounce;

  bool _isScanning = false;
  bool _isLoadingContados = true;
  bool _isSearchingProducto = false;
  bool _isSavingConteo = false;
  bool _isClosingToma = false;

  Map<String, dynamic>? _productoSeleccionado;
  List<Map<String, dynamic>> _productosContados = [];
  List<Map<String, dynamic>> _resultadosBusqueda = [];

  @override
  void initState() {
    super.initState();
    _cargarProductosContados();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scannerController.dispose();
    _searchController.dispose();
    _cantidadController.dispose();
    _cantidadFocusNode.dispose();
    super.dispose();
  }

  /// Carga la lista de productos ya contados en esta sesión de toma (conteo ciego)
  Future<void> _cargarProductosContados() async {
    setState(() => _isLoadingContados = true);
    try {
      final List<dynamic> data = await _supabase
          .from('tomas_inventario_detalle')
          .select('id, producto_id, cantidad_contada, contado_en, productos(id, sku, descripcion_1, marca, color)')
          .eq('toma_id', widget.tomaId)
          .not('cantidad_contada', 'is', null)
          .order('contado_en', ascending: false);

      if (!mounted) return;
      setState(() {
        _productosContados = List<Map<String, dynamic>>.from(data);
      });
      TomaInventarioService().actualizarProgreso(totalContados: _productosContados.length);
    } catch (e) {
      debugPrint('Error al cargar productos contados: $e');
    } finally {
      if (mounted) setState(() => _isLoadingContados = false);
    }
  }

  /// Genera variantes del código para tolerar diferencias de ceros iniciales
  /// que ocurren según el formato de código de barras (UPC-A, EAN-13, etc.)
  ///
  /// Ejemplo: "01728" → ["01728", "1728", "0000001728", "00000001728"]
  List<String> _generarVariantesCodigo(String codigo) {
    final variantes = <String>{codigo}; // siempre incluir el original

    // Sin ceros iniciales (el escáner puede entregar el valor "numérico")
    final sinCeros = codigo.replaceFirst(RegExp(r'^0+'), '');
    if (sinCeros.isNotEmpty && sinCeros != codigo) variantes.add(sinCeros);

    // Paddeado a 13 dígitos (EAN-13) y a 12 (UPC-A), solo si el código es numérico
    if (RegExp(r'^\d+$').hasMatch(codigo)) {
      if (codigo.length < 13) variantes.add(codigo.padLeft(13, '0'));
      if (codigo.length < 12) variantes.add(codigo.padLeft(12, '0'));
    }

    return variantes.toList();
  }

  /// Busca un producto por SKU exacto, código de barras o búsqueda multi-token (%)

  Future<void> _buscarProducto(String codigo, {bool isScan = false}) async {
    final q = codigo.trim();
    if (q.isEmpty) {
      setState(() {
        _productoSeleccionado = null;
        _resultadosBusqueda = [];
      });
      return;
    }

    setState(() {
      _isSearchingProducto = true;
      _productoSeleccionado = null;
      _resultadosBusqueda = [];
    });

    try {
      // 1. Solo en escaneo: intentar coincidencia exacta y auto-seleccionar
      //    Al escribir manualmente, se muestra como sugerencia (no auto-rellena)
      if (isScan) {
        // Generar variantes del código para manejar ceros iniciales (UPC-A / EAN-13)
        final List<String> variantes = _generarVariantesCodigo(q);
        final orClause = variantes
            .expand((v) => ['sku.eq.$v', 'upc.eq.$v', 'alu.eq.$v'])
            .join(',');

        final exactMatch = await _supabase
            .from('productos')
            .select('id, sku, upc, alu, descripcion_1, marca, color')
            .or(orClause)
            .maybeSingle();

        if (!mounted) return;

        if (exactMatch != null) {
          _seleccionarProducto(Map<String, dynamic>.from(exactMatch));
          return;
        }
      }

      // 2. Búsqueda multi-token (%)
      final tokens = q.split(RegExp(r'[% ]+')).where((t) => t.isNotEmpty).toList();
      if (tokens.isEmpty) return;

      List<Map<String, dynamic>> listMatch = [];
      try {
        final List<dynamic> data = await _supabase.rpc(
          'buscar_productos',
          params: {
            'p_tokens': tokens,
            'p_tienda_id': null,
            'p_modo': _modoBusqueda,
            'p_limit': 25,
          },
        );
        listMatch = List<Map<String, dynamic>>.from(data);
      } catch (rpcError) {
        debugPrint('Fallback en buscar_productos: $rpcError');
        var query = _supabase
            .from('productos')
            .select('id, sku, upc, alu, descripcion_1, marca, color');
        for (final t in tokens) {
          query = query.or('descripcion_1.ilike.%$t%,sku.ilike.%$t%,marca.ilike.%$t%');
        }
        final List<dynamic> fbData = await query.limit(25);
        listMatch = List<Map<String, dynamic>>.from(fbData);
      }

      if (!mounted) return;

      // Ordenar por prioridad si es búsqueda en modo 'cualquiera'
      if (_modoBusqueda == 'cualquiera' && tokens.length > 1) {
        int firstMatchIndex(Map<String, dynamic> prod) {
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

        listMatch.sort((a, b) {
          final idxA = firstMatchIndex(a);
          final idxB = firstMatchIndex(b);
          if (idxA != idxB) return idxA.compareTo(idxB);
          final nomA = (a['descripcion_1'] ?? '').toString().toLowerCase();
          final nomB = (b['descripcion_1'] ?? '').toString().toLowerCase();
          return nomA.compareTo(nomB);
        });
      }

      if (listMatch.isEmpty) {
        final bool? deseaCrear = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.blueAccent, width: 1.5),
            ),
            title: const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: Colors.blueAccent, size: 28),
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
                  const TextSpan(text: 'No se encontró ningún producto con el código / búsqueda:\n\n'),
                  TextSpan(
                    text: '🏷️ $q\n\n',
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const TextSpan(text: '¿Deseas registrar este nuevo producto ahora para incluirlo en la toma?'),
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
              builder: (context) => NuevoProductoPage(initialSku: q),
            ),
          );

          if (creado == true && mounted) {
            _searchController.text = q;
            _buscarProducto(q);
          }
        }
      } else if (listMatch.length == 1 && isScan) {
        // Solo auto-seleccionar con 1 resultado si vino de un escaneo
        _seleccionarProducto(listMatch.first);
      } else {
        // Escritura manual: siempre mostrar como sugerencia, nunca auto-rellenar
        setState(() => _resultadosBusqueda = listMatch);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar producto: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingProducto = false);
    }
  }

  void _seleccionarProducto(Map<String, dynamic> producto) {
    setState(() {
      _productoSeleccionado = producto;
      _resultadosBusqueda = [];
      _cantidadController.text = '1';
      _searchController.text = producto['sku'] ?? '';
    });
    // Dar foco al campo de cantidad
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _cantidadFocusNode.requestFocus();
    });
  }

  Widget _buildListaResultados() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera con conteo de resultados
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              border: const Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.blueAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selecciona el producto para contar',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${_resultadosBusqueda.length} resultados',
                    style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() {
                    _resultadosBusqueda = [];
                    _searchController.clear();
                  }),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                  ),
                ),
              ],
            ),
          ),
          // Lista de productos encontrados
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _resultadosBusqueda.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
            itemBuilder: (context, index) {
              final p = _resultadosBusqueda[index];
              final sku = p['sku'] ?? '—';
              final marca = p['marca'];
              final color = p['color'];
              final detalles = [
                'SKU: $sku',
                if (marca != null && marca.toString().isNotEmpty) 'Marca: $marca',
                if (color != null && color.toString().isNotEmpty) 'Color: $color',
              ].join(' • ');

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: index == _resultadosBusqueda.length - 1
                      ? const BorderRadius.vertical(bottom: Radius.circular(13))
                      : BorderRadius.zero,
                  onTap: () => _seleccionarProducto(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.inventory_2_outlined, color: Colors.blueAccent, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['descripcion_1'] ?? 'Sin nombre',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                detalles,
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 13),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Registra la cantidad física contada (Conteo Ciego) mediante la RPC de Supabase
  Future<void> _registrarConteo() async {
    if (_productoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona o escanea un producto primero.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final cantidad = int.tryParse(_cantidadController.text.trim());
    if (cantidad == null || cantidad < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una cantidad válida (número entero >= 0).'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() => _isSavingConteo = true);

    try {
      final productoId = _productoSeleccionado!['id'];

      await _supabase.rpc('registrar_conteo', params: {
        'p_toma_id': widget.tomaId,
        'p_producto_id': productoId,
        'p_cantidad_contada': cantidad,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conteo registrado: ${_productoSeleccionado!['descripcion_1']} = $cantidad und.'),
          backgroundColor: Colors.green,
          duration: const Duration(milliseconds: 1500),
        ),
      );

      // Limpiar selección para el siguiente escaneo
      setState(() {
        _productoSeleccionado = null;
        _searchController.clear();
        _cantidadController.text = '1';
      });

      // Recargar la lista de productos contados
      _cargarProductosContados();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar conteo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingConteo = false);
    }
  }

  /// Cierra la toma de inventario
  Future<void> _cerrarToma() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '¿Cerrar Toma de Inventario?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Al cerrar el conteo, la toma pasará a estado "pendiente_aprobacion" y no se podrán registrar más cantidades físicas en esta sesión.\n\n¿Estás seguro de finalizar?',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Cerrar Conteo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _isClosingToma = true);

    try {
      await _supabase.rpc('cerrar_toma_inventario', params: {
        'p_toma_id': widget.tomaId,
      });

      TomaInventarioService().finalizarSesion();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toma de inventario cerrada. Abriendo panel de revisión y discrepancias...'),
          backgroundColor: Colors.green,
        ),
      );

      // Redirigir a la pantalla de revisión y auditoría
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => RevisionTomaPage(tomaId: widget.tomaId),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cerrar toma de inventario: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClosingToma = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text(
          'Conteo Físico (Ciego)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.videocam_off_rounded : Icons.qr_code_scanner_rounded, color: Colors.blueAccent),
            tooltip: _isScanning ? 'Cerrar escáner' : 'Abrir escáner',
            onPressed: () => setState(() => _isScanning = !_isScanning),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refrescar contados',
            onPressed: _cargarProductosContados,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. Visor de Escáner ─────────────────────────────────────
                  if (_isScanning) _buildScannerBox(),

                  // ── 2. Barra de Búsqueda Multi-Token de Producto ────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: BuscadorProductosWidget(
                      controller: _searchController,
                      modoBusqueda: _modoBusqueda,
                      onQueryChanged: (val) {
                        _searchDebounce?.cancel();
                        final q = val.trim();
                        if (q.isEmpty) {
                          setState(() => _productoSeleccionado = null);
                          return;
                        }
                        _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                          if (mounted) _buscarProducto(q);
                        });
                      },
                      onModoChanged: (nuevoModo) {
                        setState(() => _modoBusqueda = nuevoModo);
                        if (_searchController.text.trim().isNotEmpty) {
                          _buscarProducto(_searchController.text.trim());
                        }
                      },
                      onScanPressed: () => setState(() => _isScanning = true),
                      hintText: 'Buscar por SKU, Nombre, Marca, UPC, ALU o tokens (% / espacios)...',
                      mostrarModoSelector: true,
                      mostrarChips: true,
                      mostrarEscaner: true,
                    ),
                  ),

                  if (_isSearchingProducto)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── 3. Tarjeta de Captura / Lista de resultados / Placeholder ─
                  if (_productoSeleccionado != null)
                    _buildTarjetaCaptura()
                  else if (_resultadosBusqueda.isNotEmpty)
                    _buildListaResultados()
                  else
                    _buildPlaceholderSinProducto(),

                  const SizedBox(height: 20),

                  // ── 4. Historial de Productos Contados en esta Toma ─────────
                  _buildSeccionProductosContados(),
                ],
              ),
            ),
          ),

          // ── 5. Barra Inferior con Botón de Cierre ───────────────────────────
          _buildBarraInferior(),
        ],
      ),
    );
  }

  Widget _buildScannerBox() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String code = (barcodes.first.rawValue ?? "").trim();
                  if (code.isNotEmpty) {
                    setState(() => _isScanning = false);
                    _searchController.text = code;
                    _buscarProducto(code, isScan: true);
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
    );
  }

  Widget _buildTarjetaCaptura() {
    final p = _productoSeleccionado!;

    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.blueAccent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'SKU: ${p['sku'] ?? '—'}',
                    style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => setState(() => _productoSeleccionado = null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p['descripcion_1'] ?? 'Sin descripción',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (p['marca'] != null || p['color'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'Marca: ${p['marca'] ?? '—'} | Color: ${p['color'] ?? '—'}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),

            // Campo de Cantidad Física Contada
            const Text(
              'CANTIDAD FÍSICA CONTADA (CIEGO):',
              style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cantidadController,
                    focusNode: _cantidadFocusNode,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF262626),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (_) => _registrarConteo(),
                  ),
                ),
                const SizedBox(width: 8),
                _buildQuickButton('+1', 1),
                const SizedBox(width: 6),
                _buildQuickButton('+5', 5),
                const SizedBox(width: 6),
                _buildQuickButton('+10', 10),
              ],
            ),
            const SizedBox(height: 16),

            // Botón de Confirmación
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSavingConteo ? null : _registrarConteo,
                icon: _isSavingConteo
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: Text(
                  _isSavingConteo ? 'GUARDANDO...' : 'CONFIRMAR CONTEO',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, int add) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2C2C2C),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () {
        final actual = int.tryParse(_cantidadController.text.trim()) ?? 0;
        _cantidadController.text = (actual + add).toString();
      },
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildPlaceholderSinProducto() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_scanner_rounded, color: Colors.blueAccent.withValues(alpha: 0.6), size: 48),
          const SizedBox(height: 12),
          const Text(
            'Escanea o busca un producto para contar',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'El stock teórico no se muestra durante el conteo para asegurar una auditoría física independiente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionProductosContados() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PRODUCTOS CONTADOS (${_productosContados.length})',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            if (_isLoadingContados)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
          ],
        ),
        const SizedBox(height: 10),
        if (_productosContados.isEmpty && !_isLoadingContados)
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: const Text('Aún no has registrado ningún conteo en esta toma.', style: TextStyle(color: Colors.white38, fontSize: 13)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _productosContados.length,
            itemBuilder: (context, index) {
              final item = _productosContados[index];
              final p = item['productos'] is Map ? item['productos'] as Map : {};
              final cantidad = item['cantidad_contada'] ?? 0;
              final hora = item['contado_en'] != null ? DateFormat('HH:mm:ss').format(DateTime.parse(item['contado_en']).toLocal()) : '';

              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.white10),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: Text(
                    p['descripcion_1'] ?? 'Producto #${item['producto_id']}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'SKU: ${p['sku'] ?? '—'} • Hora: $hora',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '$cantidad und.',
                      style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  onTap: () {
                    // Cargar para re-conteo si el usuario desea ajustar
                    if (p.isNotEmpty) {
                      _seleccionarProducto(Map<String, dynamic>.from(p));
                      _cantidadController.text = cantidad.toString();
                    }
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildBarraInferior() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isClosingToma ? null : _cerrarToma,
            icon: _isClosingToma
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                : const Icon(Icons.lock_clock_rounded, color: Colors.redAccent, size: 20),
            label: Text(
              _isClosingToma ? 'CERRANDO TOMA...' : 'CERRAR CONTEO / FINALIZAR TOMA',
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
