import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

import 'package:catalogo_digital_app/data/models/kardex_model.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';

class KardexScreen extends StatefulWidget {
  final String? initialProductoId;
  final String? initialProductoNombre;
  final String? initialSku;

  const KardexScreen({
    super.key,
    this.initialProductoId,
    this.initialProductoNombre,
    this.initialSku,
  });

  @override
  State<KardexScreen> createState() => _KardexScreenState();
}

class _KardexScreenState extends State<KardexScreen> {
  final _supabase = Supabase.instance.client;
  final _fmtDate = DateFormat('dd/MM/yyyy HH:mm');
  final _fmtShortDate = DateFormat('dd/MM/yyyy');

  // Filtros
  String? _selectedProductoId;
  String? _selectedProductoLabel;
  int? _selectedTiendaId;
  DateTimeRange? _dateRange;

  // Paginación
  int _currentPage = 0;
  static const int _rowsPerPage = 20;

  // Listas de datos
  List<KardexMovimiento> _movimientos = [];
  List<Map<String, dynamic>> _tiendasList = [];
  List<Map<String, dynamic>> _productosSugeridos = [];

  bool _cargando = true;
  bool _buscandoProductos = false;
  bool _exportando = false;
  String? _error;

  final TextEditingController _productoSearchCtrl = TextEditingController();

  // ── Ciclo de vida ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    if (widget.initialProductoId != null) {
      _selectedProductoId = widget.initialProductoId;
      _selectedProductoLabel =
          widget.initialProductoNombre ?? widget.initialSku ?? '';
      _productoSearchCtrl.text = _selectedProductoLabel!;
    }
    _cargarTiendas();
    _cargarMovimientos();
  }

  @override
  void dispose() {
    _productoSearchCtrl.dispose();
    super.dispose();
  }

  // ── Carga de datos ───────────────────────────────────────────────────────────
  Future<void> _cargarTiendas() async {
    try {
      final res =
          await _supabase.from('tiendas').select('id, nombre').order('nombre');
      if (mounted) {
        setState(() {
          _tiendasList = List<Map<String, dynamic>>.from(res as List);
        });
      }
    } catch (e) {
      debugPrint('Error cargando tiendas: $e');
    }
  }

  Future<void> _buscarProductos(String pattern) async {
    if (pattern.trim().length < 2) {
      setState(() => _productosSugeridos = []);
      return;
    }
    setState(() => _buscandoProductos = true);
    try {
      final q = pattern.trim();
      final List<String> tokens = q.isEmpty
          ? []
          : (q.contains('%')
              ? q
                  .split('%')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList()
              : [q]);

      final List<dynamic> res;
      if (tokens.isNotEmpty) {
        res = await _supabase.rpc('buscar_productos', params: {
          'p_tokens': tokens,
          'p_limit': 15,
          'p_offset': 0,
          'p_modo': 'cualquiera',
        });
      } else {
        res = [];
      }
      if (mounted) {
        setState(() {
          _productosSugeridos = List<Map<String, dynamic>>.from(res);
          _buscandoProductos = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _buscandoProductos = false);
    }
  }

  Future<void> _cargarMovimientos() async {
    setState(() {
      _cargando = true;
      _error = null;
      _currentPage = 0;
    });

    try {
      var query = _supabase.from('kardex_movimientos').select(
          '*, lote, unidad_medida, productos(sku, descripcion_1), tiendas(nombre)');

      if (_selectedProductoId != null && _selectedProductoId!.isNotEmpty) {
        query = query.eq('producto_id', _selectedProductoId!);
      }
      if (_selectedTiendaId != null) {
        query = query.eq('tienda_id', _selectedTiendaId!);
      }
      if (_dateRange != null) {
        final start = DateTime(_dateRange!.start.year, _dateRange!.start.month,
            _dateRange!.start.day, 0, 0, 0);
        final end = DateTime(_dateRange!.end.year, _dateRange!.end.month,
            _dateRange!.end.day, 23, 59, 59);
        query = query
            .gte('created_at', start.toIso8601String())
            .lte('created_at', end.toIso8601String());
      }

      final List<dynamic> res =
          await query.order('created_at', ascending: false).limit(500);

      final list = res
          .map((j) => KardexMovimiento.fromJson(Map<String, dynamic>.from(j)))
          .toList();

      // Enriquecer con nombres de usuario desde public.perfiles
      final userIds =
          list.map((m) => m.usuarioId).whereType<String>().toSet().toList();
      if (userIds.isNotEmpty) {
        try {
          final perfilesRes = await _supabase
              .from('perfiles')
              .select('id, nombre, email')
              .inFilter('id', userIds);
          final Map<String, String> nombresMap = {
            for (final p in perfilesRes as List)
              p['id'].toString(): (p['nombre'] != null && p['nombre'].toString().trim().isNotEmpty)
                  ? p['nombre'].toString().trim()
                  : (p['email'] ?? '').toString().trim()
          };
          for (int i = 0; i < list.length; i++) {
            final uid = list[i].usuarioId;
            if (uid != null && nombresMap.containsKey(uid)) {
              list[i] = list[i].copyWith(usuarioNombre: nombresMap[uid]);
            }
          }
        } catch (e) {
          debugPrint('No se pudo enriquecer nombres de usuario: $e');
        }
      }

      if (mounted) {
        setState(() {
          _movimientos = list;
          _cargando = false;
        });
      }
    } catch (e) {
      debugPrint('Error al consultar kardex: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  // ── Exportar Excel ───────────────────────────────────────────────────────────
  Future<void> _exportarExcel() async {
    if (_movimientos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay datos de Kardex para exportar.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    setState(() => _exportando = true);
    try {
      final excel = Excel.createExcel();
      const sheetName = 'Kardex_Movimientos';
      excel.rename('Sheet1', sheetName);
      final Sheet sheetObject = excel[sheetName];

      sheetObject.appendRow([
        TextCellValue('ID'),
        TextCellValue('Cod. Centro'),
        TextCellValue('Nom. Centro'),
        TextCellValue('Cod. Producto'),
        TextCellValue('Nom. Producto'),
        TextCellValue('Lote'),
        TextCellValue('Fecha'),
        TextCellValue('Tip. Doc.'),
        TextCellValue('Nro. Doc.'),
        TextCellValue('Cantidad'),
        TextCellValue('UM'),
        TextCellValue('Stock'),
        TextCellValue('Costo Unitario (S/.)'),
        TextCellValue('Costo Medio (S/.)'),
        TextCellValue('Usuario'),
      ]);

      for (final m in _movimientos) {
        sheetObject.appendRow([
          TextCellValue(m.id?.toString() ?? ''),
          TextCellValue(m.tiendaId?.toString() ?? ''),
          TextCellValue(m.tiendaNombre ?? ''),
          TextCellValue(m.productoSku ?? ''),
          TextCellValue(m.productoDescripcion ?? ''),
          TextCellValue(m.lote ?? ''),
          TextCellValue(m.createdAt != null
              ? _fmtShortDate.format(m.createdAt!.toLocal())
              : ''),
          TextCellValue(m.tipDocAbreviado),
          TextCellValue(m.origenId ?? ''),
          DoubleCellValue(m.cantidad),
          TextCellValue(m.unidadMedida ?? 'UND'),
          DoubleCellValue(m.stockResultante ?? 0.0),
          DoubleCellValue(m.costoUnitario ?? 0.0),
          DoubleCellValue(m.costoMedioMomento ?? 0.0),
          TextCellValue(m.usuarioNombre ?? ''),
        ]);
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) throw Exception('No se pudo generar el archivo Excel.');

      final fileName =
          'Kardex_Reporte_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([fileBytes],
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final file = io.File(filePath);
        await file.writeAsBytes(fileBytes);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            subject: 'Reporte de Kardex - $fileName',
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Reporte Excel exportado con éxito'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exportando Excel: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ── Paginación ───────────────────────────────────────────────────────────────
  List<KardexMovimiento> get _movimientosPagina {
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, _movimientos.length);
    if (start >= _movimientos.length) return [];
    return _movimientos.sublist(start, end);
  }

  int get _totalPages =>
      (_movimientos.length / _rowsPerPage).ceil().clamp(1, 9999);

  // ── Build principal ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool esDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      drawer: const MenuLateral(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kardex / Movimientos de Inventario',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            if (_selectedProductoLabel != null)
              Text(
                'Filtro: $_selectedProductoLabel',
                style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _cargarMovimientos,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _exportando
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.tealAccent),
                    ),
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent.shade700,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _exportarExcel,
                    icon: const Icon(Icons.file_download, size: 18),
                    label: Text(
                      esDesktop ? 'Exportar Excel' : 'Excel',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBarraFiltros(context),
          Expanded(
            child: _cargando
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.tealAccent))
                : _error != null
                    ? _buildErrorView()
                    : _movimientos.isEmpty
                        ? _buildEmptyView()
                        : esDesktop
                            ? _buildDesktopTable()
                            : _buildMobileCardsList(),
          ),
        ],
      ),
    );
  }

  // ── Barra de Filtros (tema oscuro) ───────────────────────────────────────────
  Widget _buildBarraFiltros(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Fila 1: Producto + Tienda
          Row(
            children: [
              // Buscador Producto
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFiltroLabel('Producto'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _productoSearchCtrl,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Buscar por SKU o Nombre...',
                        hintStyle: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search,
                            color: Colors.tealAccent, size: 18),
                        suffixIcon: _buscandoProductos
                            ? const Padding(
                                padding: EdgeInsets.all(10.0),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.tealAccent),
                                ),
                              )
                            : _productoSearchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: Colors.white54, size: 16),
                                    onPressed: () {
                                      _productoSearchCtrl.clear();
                                      setState(() {
                                        _selectedProductoId = null;
                                        _selectedProductoLabel = null;
                                        _productosSugeridos = [];
                                      });
                                      _cargarMovimientos();
                                    },
                                  )
                                : null,
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        if (_selectedProductoId != null) {
                          _selectedProductoId = null;
                          _selectedProductoLabel = null;
                        }
                        _buscarProductos(val);
                      },
                    ),
                    if (_productosSugeridos.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 6)
                          ],
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _productosSugeridos.length,
                          itemBuilder: (ctx, idx) {
                            final p = _productosSugeridos[idx];
                            return ListTile(
                              dense: true,
                              title: Text(
                                p['descripcion_1']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                              subtitle: Text(
                                'SKU: ${p['sku'] ?? '—'}',
                                style: const TextStyle(
                                    color: Colors.tealAccent, fontSize: 11),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedProductoId = p['id'].toString();
                                  _selectedProductoLabel =
                                      '${p['sku']} - ${p['descripcion_1']}';
                                  _productoSearchCtrl.text =
                                      _selectedProductoLabel!;
                                  _productosSugeridos = [];
                                });
                                _cargarMovimientos();
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Selector Tienda/Centro
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFiltroLabel('Centro / Almacén'),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _selectedTiendaId,
                          dropdownColor: const Color(0xFF2A2A2A),
                          isExpanded: true,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          icon: const Icon(Icons.store,
                              color: Colors.tealAccent, size: 18),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todas las Tiendas',
                                  overflow: TextOverflow.ellipsis),
                            ),
                            ..._tiendasList.map((t) {
                              return DropdownMenuItem<int?>(
                                value: int.tryParse(t['id'].toString()),
                                child: Text(t['nombre']?.toString() ?? '',
                                    overflow: TextOverflow.ellipsis),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedTiendaId = val);
                            _cargarMovimientos();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Fila 2: Rango de fechas
          Row(
            children: [
              _buildFiltroLabel('Rango de Fechas:'),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: _dateRange,
                      builder: (ctx, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: ColorScheme.dark(
                              primary: Colors.tealAccent.shade400,
                              onPrimary: Colors.black,
                              surface: const Color(0xFF1E1E1E),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() => _dateRange = picked);
                      _cargarMovimientos();
                    }
                  },
                  icon: const Icon(Icons.date_range,
                      color: Colors.tealAccent, size: 16),
                  label: Text(
                    _dateRange == null
                        ? 'Todas las Fechas'
                        : '${_fmtShortDate.format(_dateRange!.start)}  →  ${_fmtShortDate.format(_dateRange!.end)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_dateRange != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Limpiar Fechas',
                  icon:
                      const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                  onPressed: () {
                    setState(() => _dateRange = null);
                    _cargarMovimientos();
                  },
                ),
              ],
              const SizedBox(width: 10),
              // Contador de resultados
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '${_movimientos.length} registros',
                  style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── Error View ───────────────────────────────────────────────────────────────
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text('Error al cargar movimientos:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _cargarMovimientos,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  // ── Empty View ───────────────────────────────────────────────────────────────
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_toggle_off, color: Colors.white24, size: 56),
          const SizedBox(height: 12),
          const Text(
            'No se encontraron movimientos de Kardex',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Intenta cambiar los filtros de búsqueda',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Vista Desktop — tabla con 12 columnas ────────────────────────────────────
  Widget _buildDesktopTable() {
    final pagina = _movimientosPagina;

    return Column(
      children: [
        // Tabla con scroll horizontal
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildDataTable(pagina),
            ),
          ),
        ),
        // Paginador
        _buildPaginador(),
      ],
    );
  }

  Widget _buildDataTable(List<KardexMovimiento> pagina) {
    // Estilo cabecera
    const headerStyle = TextStyle(
      color: Colors.tealAccent,
      fontWeight: FontWeight.bold,
      fontSize: 11,
      letterSpacing: 0.5,
    );

    return DataTable(
      headingRowColor: WidgetStateProperty.all(const Color(0xFF1A2A2A)),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return const Color(0xFF1E3A3A);
        }
        return const Color(0xFF141414);
      }),
      headingRowHeight: 42,
      dataRowMinHeight: 44,
      dataRowMaxHeight: 52,
      columnSpacing: 18,
      horizontalMargin: 16,
      dividerThickness: 0.5,
      columns: const [
        DataColumn(label: Text('ID', style: headerStyle)),
        DataColumn(label: Text('COD.\nCENTRO', style: headerStyle)),
        DataColumn(label: Text('NOM.\nCENTRO', style: headerStyle)),
        DataColumn(label: Text('COD.\nPRODUCTO', style: headerStyle)),
        DataColumn(label: Text('NOM. PRODUCTO', style: headerStyle)),
        DataColumn(label: Text('LOTE', style: headerStyle)),
        DataColumn(label: Text('FECHA', style: headerStyle)),
        DataColumn(label: Text('TIP.\nDOC.', style: headerStyle)),
        DataColumn(label: Text('NRO. DOC.', style: headerStyle)),
        DataColumn(label: Text('CANTIDAD', style: headerStyle)),
        DataColumn(label: Text('UM', style: headerStyle)),
        DataColumn(label: Text('STOCK', style: headerStyle)),
      ],
      rows: pagina.asMap().entries.map((entry) {
        final m = entry.value;
        final idx = (_currentPage * _rowsPerPage) + entry.key;
        final esSalida = m.tipoMovimiento.toUpperCase() == 'SALIDA';
        final esEntrada = m.tipoMovimiento.toUpperCase() == 'ENTRADA';

        // Color de fila alternada
        final rowBg = idx % 2 == 0
            ? const Color(0xFF141414)
            : const Color(0xFF181818);

        return DataRow(
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFF1E3A3A);
            }
            return rowBg;
          }),
          cells: [
            // ID (truncado, clicable para copiar)
            DataCell(
              Tooltip(
                message: m.id?.toString() ?? '',
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: m.id?.toString() ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ID copiado al portapapeles'),
                        duration: Duration(seconds: 1),
                        backgroundColor: Colors.tealAccent,
                      ),
                    );
                  },
                  child: Text(
                    _truncarId(m.id?.toString() ?? ''),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),

            // COD. CENTRO
            DataCell(Text(
              m.tiendaId?.toString() ?? '—',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            )),

            // NOM. CENTRO
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  m.tiendaNombre ?? '—',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // COD. PRODUCTO (SKU)
            DataCell(Text(
              m.productoSku ?? '—',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            )),

            // NOM. PRODUCTO
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  m.productoDescripcion ?? '—',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // LOTE
            DataCell(Text(
              m.lote ?? '—',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            )),

            // FECHA
            DataCell(Text(
              m.createdAt != null
                  ? _fmtShortDate.format(m.createdAt!.toLocal())
                  : '—',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            )),

            // TIP. DOC.
            DataCell(_buildTipDocBadge(m.tipDocAbreviado, m.tipoMovimiento)),

            // NRO. DOC. — estilo link azul
            DataCell(
              GestureDetector(
                onTap: () {
                  if (m.origenId != null && m.origenId!.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: m.origenId!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('N° Doc copiado: ${m.origenId}'),
                        duration: const Duration(seconds: 1),
                        backgroundColor: Colors.blueAccent,
                      ),
                    );
                  }
                },
                child: Text(
                  m.origenId ?? '—',
                  style: TextStyle(
                    color: m.origenId != null && m.origenId!.isNotEmpty
                        ? Colors.blueAccent.shade100
                        : Colors.white38,
                    fontSize: 12,
                    decoration: m.origenId != null && m.origenId!.isNotEmpty
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: Colors.blueAccent.shade100,
                  ),
                ),
              ),
            ),

            // CANTIDAD con badge flecha
            DataCell(_buildCantidadBadge(m.cantidad, esEntrada, esSalida)),

            // UM
            DataCell(Text(
              m.unidadMedida ?? 'UND',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            )),

            // STOCK (resultante)
            DataCell(Text(
              m.stockResultante?.toStringAsFixed(0) ?? '—',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            )),
          ],
        );
      }).toList(),
    );
  }

  // ── Paginador ────────────────────────────────────────────────────────────────
  Widget _buildPaginador() {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            'Páginas:',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 8),
          // Botón anterior
          _buildPageButton(
            icon: Icons.chevron_left,
            enabled: _currentPage > 0,
            onTap: () => setState(() => _currentPage--),
          ),
          const SizedBox(width: 4),
          // Números de página
          ..._buildNumerosPagina(),
          const SizedBox(width: 4),
          // Botón siguiente
          _buildPageButton(
            icon: Icons.chevron_right,
            enabled: _currentPage < _totalPages - 1,
            onTap: () => setState(() => _currentPage++),
          ),
          const Spacer(),
          // Info filas
          Text(
            'Mostrando ${(_currentPage * _rowsPerPage) + 1}–${((_currentPage + 1) * _rowsPerPage).clamp(0, _movimientos.length)} de ${_movimientos.length}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(
      {required IconData icon,
      required bool enabled,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon,
            color: enabled ? Colors.white70 : Colors.white24, size: 18),
      ),
    );
  }

  List<Widget> _buildNumerosPagina() {
    final List<Widget> widgets = [];
    const int maxVisible = 7;
    final int total = _totalPages;

    List<int> paginas = [];
    if (total <= maxVisible) {
      paginas = List.generate(total, (i) => i);
    } else {
      paginas.add(0);
      int start = (_currentPage - 2).clamp(1, total - 5);
      int end = (start + 4).clamp(4, total - 1);
      start = (end - 4).clamp(1, total - 5);
      if (start > 1) paginas.add(-1); // ellipsis
      for (int i = start; i <= end; i++) {
        paginas.add(i);
      }
      if (end < total - 1) paginas.add(-1); // ellipsis
      paginas.add(total - 1);
    }

    for (final p in paginas) {
      if (p == -1) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('…', style: TextStyle(color: Colors.white38)),
        ));
      } else {
        final isActive = p == _currentPage;
        widgets.add(
          GestureDetector(
            onTap: () => setState(() => _currentPage = p),
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.tealAccent.shade700
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive ? Colors.tealAccent : Colors.white12,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${p + 1}',
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.white70,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  // ── Vista Móvil — Cards ──────────────────────────────────────────────────────
  Widget _buildMobileCardsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _movimientos.length,
      itemBuilder: (context, index) {
        final m = _movimientos[index];
        final esEntrada = m.tipoMovimiento.toUpperCase() == 'ENTRADA';
        final esSalida = m.tipoMovimiento.toUpperCase() == 'SALIDA';

        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: TIP.DOC badge + Fecha
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildTipDocBadge(m.tipDocAbreviado, m.tipoMovimiento),
                    Text(
                      m.createdAt != null
                          ? _fmtDate.format(m.createdAt!.toLocal())
                          : '—',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  m.productoDescripcion ?? 'Producto sin descripción',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                Text(
                  'SKU: ${m.productoSku ?? '—'}  |  ${m.tiendaNombre ?? 'General'}  (ID: ${m.tiendaId ?? '—'})',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (m.lote != null)
                  Text('Lote: ${m.lote}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10)),
                const Divider(color: Colors.white12, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCantidadBadge(m.cantidad, esEntrada, esSalida),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Stock resultante',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 10)),
                        Text(
                          m.stockResultante?.toStringAsFixed(0) ?? '—',
                          style: const TextStyle(
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Doc: ${m.origenId ?? '—'}',
                      style: TextStyle(
                        color: m.origenId != null
                            ? Colors.blueAccent.shade100
                            : Colors.white54,
                        fontSize: 11,
                        decoration: m.origenId != null
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
                    Text(
                      'UM: ${m.unidadMedida ?? 'UND'}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                if (m.usuarioNombre != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Responsable: ${m.usuarioNombre}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Widgets helper ───────────────────────────────────────────────────────────

  /// Badge para TIP. DOC. — VTA, COM, AJU
  Widget _buildTipDocBadge(String abrev, String tipoMovimiento) {
    Color bg;
    Color fg;
    switch (tipoMovimiento.toUpperCase()) {
      case 'ENTRADA':
        bg = Colors.green.shade900.withValues(alpha: 0.55);
        fg = Colors.greenAccent;
        break;
      case 'SALIDA':
        bg = Colors.red.shade900.withValues(alpha: 0.55);
        fg = Colors.redAccent;
        break;
      case 'AJUSTE':
        bg = Colors.blue.shade900.withValues(alpha: 0.55);
        fg = Colors.blueAccent;
        break;
      default:
        bg = Colors.grey.shade800;
        fg = Colors.white70;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        abrev,
        style: TextStyle(
            color: fg, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  /// Badge de cantidad con flecha (↓ rojo = salida, ↑ verde = entrada)
  Widget _buildCantidadBadge(
      double cantidad, bool esEntrada, bool esSalida) {
    final color = esEntrada
        ? Colors.greenAccent
        : esSalida
            ? Colors.redAccent
            : Colors.white70;
    final bgColor = esEntrada
        ? Colors.green.shade900.withValues(alpha: 0.4)
        : esSalida
            ? Colors.red.shade900.withValues(alpha: 0.4)
            : Colors.grey.shade800.withValues(alpha: 0.4);
    final icon = esEntrada
        ? Icons.arrow_upward_rounded
        : esSalida
            ? Icons.arrow_downward_rounded
            : Icons.remove;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            cantidad.toStringAsFixed(0),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _truncarId(String id) {
    if (id.length > 8) return '${id.substring(0, 8)}…';
    return id;
  }
}
