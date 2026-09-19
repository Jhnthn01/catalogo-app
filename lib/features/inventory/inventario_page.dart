import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/features/inventory/nuevo_producto_page.dart';
import 'package:catalogo_digital_app/features/inventory/carga_masiva_page.dart';
import 'package:catalogo_digital_app/features/catalog/detalle_producto_page.dart';
import 'package:catalogo_digital_app/widgets/filtros_jerarquia.dart';
import 'package:catalogo_digital_app/widgets/buscador_productos_widget.dart';
import 'package:catalogo_digital_app/features/inventory/tabla_detallada_inventario_screen.dart';
import 'package:catalogo_digital_app/features/inventory/kardex_screen.dart';

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
  String _modoBusqueda = 'cualquiera';

  bool _isScanning = false;
  bool _isLoading = false;
  bool _hasMore = true;
  int _paginaActual = 0;
  final int _tamanhoPagina = 25;
  int _fetchId = 0;

  Timer? _debounce;

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

  void _onSearchChanged(String val) {
    _searchQuery = val;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _reiniciarLista();
      if (_isLoading) setState(() => _isLoading = false);
      _cargarMasProductos();
    });
  }

  /// Devuelve el índice del primer token de [tokens] que aparece
  /// (como subcadena, case-insensitive) en cualquier campo del producto.
  /// Si ninguno coincide retorna tokens.length (va al final del sort).
  int _firstMatchIndex(Map<String, dynamic> product, List<String> tokens) {
    final fields = [
      (product['descripcion_1'] ?? '').toString().toLowerCase(),
      (product['sku'] ?? '').toString().toLowerCase(),
      (product['upc'] ?? '').toString().toLowerCase(),
      (product['marca'] ?? '').toString().toLowerCase(),
      (product['alu'] ?? '').toString().toLowerCase(),
    ];
    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i].toLowerCase();
      if (fields.any((f) => f.contains(t))) return i;
    }
    return tokens.length;
  }

  Future<void> _cargarMasProductos() async {
    if (!mounted || _isLoading || !_hasMore) return;

    final currentFetchId = ++_fetchId;
    setState(() => _isLoading = true);

    try {
      final tiendaId = TiendaService().tiendaActivaId.value;
      final rol = TiendaService().usuarioRol?.toLowerCase() ?? 'cliente';
      final bool esAdmin = rol == 'admin' || rol == 'administrador' || rol == 'gerente';

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

        final List<dynamic> data = await Supabase.instance.client.rpc(
          'buscar_productos',
          params: params,
        );

        final list = List<Map<String, dynamic>>.from(data);

        if (_modoBusqueda == 'cualquiera' && tokens.length > 1) {
          list.sort((a, b) {
            final idxA = _firstMatchIndex(a, tokens);
            final idxB = _firstMatchIndex(b, tokens);
            if (idxA != idxB) return idxA.compareTo(idxB);
            final nomA = (a['descripcion_1'] ?? '').toString().toLowerCase();
            final nomB = (b['descripcion_1'] ?? '').toString().toLowerCase();
            return nomA.compareTo(nomB);
          });
        }

        if (!mounted || currentFetchId != _fetchId) return;

        setState(() {
          _productos
            ..clear()
            ..addAll(list);
          _isLoading = false;
          _hasMore = false;
        });
      } else {
        final String invJoin = (tiendaId != null || !esAdmin)
            ? 'inventario!inner(stock, tienda_id, actualizado_at, usuario_id)'
            : 'inventario(stock, tienda_id, actualizado_at, usuario_id)';

        final String selectFields =
            'id, sku, upc, alu, marca, categoria, clase, sub_clase, estilo, descripcion_1, descripcion_2, color, costo, precio_venta, ultimo_costo, fecha_ultimo_costo, costo_medio, created_at, modificado_por, modificado_at, $invJoin';

        var query = Supabase.instance.client.from('productos').select(selectFields);
        if (tiendaId != null) {
          query = query.eq('inventario.tienda_id', tiendaId);
        } else if (!esAdmin) {
          query = query.eq('inventario.tienda_id', -1);
        }
        if (_catFiltro != null) query = query.eq('categoria', _catFiltro!);
        if (_claseFiltro != null) query = query.eq('clase', _claseFiltro!);
        if (_subClaseFiltro != null) query = query.eq('sub_clase', _subClaseFiltro!);

        final int desde = _paginaActual * _tamanhoPagina;
        final int hasta = desde + _tamanhoPagina - 1;
        final List<dynamic> data =
            await query.order('descripcion_1').range(desde, hasta);

        if (!mounted || currentFetchId != _fetchId) return;

        final newItems = List<Map<String, dynamic>>.from(data);
        setState(() {
          _productos.addAll(newItems);
          _paginaActual++;
          _isLoading = false;
          if (data.length < _tamanhoPagina) _hasMore = false;
        });
        _enriquecerModificados(newItems);
      }
    } catch (e) {
      if (mounted && currentFetchId == _fetchId) {
        setState(() => _isLoading = false);
        debugPrint("Error _cargarMasProductos: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al buscar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _enriquecerModificados(List<Map<String, dynamic>> lista) async {
    final ids = lista
        .map((p) => p['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      final List<dynamic> res = await Supabase.instance.client
          .from('kardex_movimientos')
          .select('producto_id, usuario_id, created_at')
          .inFilter('producto_id', ids)
          .order('created_at', ascending: false);

      final Map<String, Map<String, dynamic>> ultimosMovs = {};
      for (final row in res) {
        if (row is Map) {
          final pid = row['producto_id']?.toString();
          if (pid != null && !ultimosMovs.containsKey(pid)) {
            ultimosMovs[pid] = Map<String, dynamic>.from(row);
          }
        }
      }

      final Set<String> userIds = {};
      for (final m in ultimosMovs.values) {
        final uid = m['usuario_id']?.toString();
        if (uid != null && uid.isNotEmpty) userIds.add(uid);
      }

      for (final p in lista) {
        final modPor = p['modificado_por']?.toString();
        if (modPor != null && modPor.isNotEmpty) userIds.add(modPor);

        final inv = p['inventario'];
        if (inv is List) {
          for (final row in inv) {
            if (row is Map && row['usuario_id'] != null) {
              final uid = row['usuario_id'].toString();
              if (uid.isNotEmpty) userIds.add(uid);
            }
          }
        } else if (inv is Map && inv['usuario_id'] != null) {
          final uid = inv['usuario_id'].toString();
          if (uid.isNotEmpty) userIds.add(uid);
        }
      }

      Map<String, String> userNames = {};
      if (userIds.isNotEmpty) {
        final perfilesRes = await Supabase.instance.client
            .from('perfiles')
            .select('id, nombre, email')
            .inFilter('id', userIds.toList());
        userNames = {
          for (final p in perfilesRes as List)
            p['id'].toString(): (p['nombre'] != null && p['nombre'].toString().trim().isNotEmpty)
                ? p['nombre'].toString().trim()
                : (p['email'] ?? '').toString().trim()
        };
      }

      for (final p in lista) {
        final pid = p['id']?.toString();

        DateTime? mejorFecha;
        String? mejorUsuario;

        if (p['modificado_at'] != null) {
          final f = DateTime.tryParse(p['modificado_at'].toString());
          if (f != null) {
            mejorFecha = f;
            final uid = p['modificado_por']?.toString();
            mejorUsuario = (uid != null && userNames.containsKey(uid)) ? userNames[uid] : null;
          }
        }

        if (pid != null && ultimosMovs.containsKey(pid)) {
          final mov = ultimosMovs[pid]!;
          final f = DateTime.tryParse(mov['created_at']?.toString() ?? '');
          if (f != null && (mejorFecha == null || f.isAfter(mejorFecha))) {
            mejorFecha = f;
            final uid = mov['usuario_id']?.toString();
            mejorUsuario = (uid != null && userNames.containsKey(uid)) ? userNames[uid] : null;
          }
        }

        final inv = p['inventario'];
        Map? invMap;
        if (inv is List && inv.isNotEmpty && inv.first is Map) {
          invMap = inv.first as Map;
        } else if (inv is Map) {
          invMap = inv;
        }
        if (invMap != null && invMap['actualizado_at'] != null) {
          final f = DateTime.tryParse(invMap['actualizado_at'].toString());
          if (f != null && (mejorFecha == null || f.isAfter(mejorFecha))) {
            mejorFecha = f;
            final uid = invMap['usuario_id']?.toString();
            if (uid != null && userNames.containsKey(uid)) {
              mejorUsuario = userNames[uid];
            }
          }
        }

        if (mejorFecha != null) {
          p['modificado_fecha'] = mejorFecha.toIso8601String();
        }
        if (mejorUsuario != null) {
          p['modificado_usuario'] = mejorUsuario;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error al enriquecer modificado en inventario_page: $e');
    }
  }


  @override
  void dispose() {
    _debounce?.cancel();
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
            .select('stock, tiendas(nombre), productos(sku, upc, alu, marca, categoria, clase, sub_clase, estilo, descripcion_1, descripcion_2, color, costo, precio_venta)')
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
      rows.add(['SKU', 'UPC', 'ALU', 'Marca', 'Categoria', 'Clase', 'Subclase', 'Estilo', 'Descripcion', 'Descripcion_2', 'Color', 'Costo', 'Precio', 'Stock', 'Tienda']);
      
      for (var row in allRows) {
        final p = row['productos'] ?? {};
        rows.add([
          p['sku'] ?? '',
          p['upc'] ?? '',
          p['alu'] ?? '',
          p['marca'] ?? '',
          p['categoria'] ?? '',
          p['clase'] ?? '',
          p['sub_clase'] ?? '',
          p['estilo'] ?? '',
          p['descripcion_1'] ?? '',
          p['descripcion_2'] ?? '',
          p['color'] ?? '',
          p['costo'] ?? 0,
          p['precio_venta'] ?? 0,
          row['stock'] ?? 0,
          nombreTienda
        ]);
      }
      
      String csvData = Csv().encode(rows);
      if (kIsWeb) {
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
      } else {
        final directory = await getTemporaryDirectory();
        final fileName = 'maestro_${nombreTienda.replaceAll(' ', '_')}.csv';
        final filePath = '${directory.path}/$fileName';
        final file = io.File(filePath);
        await file.writeAsString(csvData, encoding: utf8);
        
        await Share.shareXFiles(
          [XFile(filePath, name: fileName)],
          subject: 'Maestro de Inventario - $nombreTienda',
        );
      }
      
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
    final bool esEscritorio = MediaQuery.of(context).size.width > 800;

    if (esEscritorio) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text("Inventario / Maestro de Productos"),
          backgroundColor: const Color(0xFF1E1E1E),
          actions: [
            IconButton(
              icon: const Icon(Icons.history_toggle_off, color: Colors.tealAccent),
              tooltip: 'Ver Kardex / Movimientos',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const KardexScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.upload_file, color: Colors.blueAccent),
              tooltip: 'Importar CSV (Carga Masiva)',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CargaMasivaPage()),
                ).then((val) {
                  if (val == true) {
                    _reiniciarLista();
                    _cargarMasProductos();
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.download, color: Colors.greenAccent),
              tooltip: 'Exportar Maestro CSV',
              onPressed: _exportarCSV,
            ),
          ],
        ),
        body: TablaDetalladaInventarioScreen(
          onRefreshPadre: () {
            _reiniciarLista();
            _cargarMasProductos();
          },
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Inventario"),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_toggle_off, color: Colors.tealAccent),
            tooltip: 'Ver Kardex / Movimientos',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const KardexScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file, color: Colors.blueAccent),
            tooltip: 'Importar CSV (Carga Masiva)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CargaMasivaPage()),
              ).then((val) {
                if (val == true) {
                  _reiniciarLista();
                  _cargarMasProductos();
                }
              });
            },
          ),
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
            child: _isScanning
                ? _buildScanner()
                : BuscadorProductosWidget(
                    controller: _searchController,
                    modoBusqueda: _modoBusqueda,
                    onQueryChanged: _onSearchChanged,
                    onModoChanged: (nuevoModo) {
                      setState(() => _modoBusqueda = nuevoModo);
                      _reiniciarLista();
                      if (_isLoading) setState(() => _isLoading = false);
                      _cargarMasProductos();
                    },
                    onScanPressed: () => setState(() => _isScanning = true),
                  ),
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
                                  Builder(
                                    builder: (context) {
                                      final String? uName = prod['modificado_usuario']?.toString();
                                      final String userText = (uName != null && uName.trim().isNotEmpty)
                                          ? uName.trim().toUpperCase()
                                          : '—';

                                      DateTime? modFecha;
                                      if (prod['modificado_fecha'] != null) {
                                        modFecha = DateTime.tryParse(prod['modificado_fecha'].toString());
                                      } else if (prod['created_at'] != null) {
                                        modFecha = DateTime.tryParse(prod['created_at'].toString());
                                      }

                                      if (userText == '—' && modFecha == null) return const SizedBox.shrink();

                                      final dateStr = modFecha != null
                                          ? DateFormat('dd/MM/yyyy HH:mm:ss').format(modFecha.toLocal())
                                          : '—';

                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Modificado: $userText  |  $dateStr',
                                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                                        ),
                                      );
                                    },
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
    if (prod.containsKey('stock') && prod['stock'] != null) {
      final s = prod['stock'];
      if (s is num) return s.round();
    }
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
