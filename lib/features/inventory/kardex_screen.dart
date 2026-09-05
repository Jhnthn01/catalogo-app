import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
  final _fmtCurrency = NumberFormat.currency(symbol: 'S/.', decimalDigits: 2);
  final _fmtDate = DateFormat('dd/MM/yyyy HH:mm');
  final _fmtShortDate = DateFormat('dd/MM/yyyy');

  // Filtros
  String? _selectedProductoId;
  String? _selectedProductoLabel;
  int? _selectedTiendaId; // null = Todas las tiendas
  DateTimeRange? _dateRange;

  // Listas de datos
  List<KardexMovimiento> _movimientos = [];
  List<Map<String, dynamic>> _tiendasList = [];
  List<Map<String, dynamic>> _productosSugeridos = [];

  bool _cargando = true;
  bool _buscandoProductos = false;
  bool _exportando = false;
  String? _error;

  final TextEditingController _productoSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialProductoId != null) {
      _selectedProductoId = widget.initialProductoId;
      _selectedProductoLabel = widget.initialProductoNombre ?? widget.initialSku ?? '';
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

  Future<void> _cargarTiendas() async {
    try {
      final res = await _supabase.from('tiendas').select('id, nombre').order('nombre');
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
              ? q.split('%').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
              : [q]);

      final List<dynamic> res;
      if (tokens.isNotEmpty) {
        final params = <String, dynamic>{
          'p_tokens': tokens,
          'p_limit': 15,
          'p_offset': 0,
        };
        res = await _supabase.rpc('buscar_productos', params: params);
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
    });

    try {
      var query = _supabase.from('kardex_movimientos').select(
          '*, productos(sku, descripcion_1), tiendas(nombre)');

      if (_selectedProductoId != null && _selectedProductoId!.isNotEmpty) {
        query = query.eq('producto_id', _selectedProductoId!);
      }

      if (_selectedTiendaId != null) {
        query = query.eq('tienda_id', _selectedTiendaId!);
      }

      if (_dateRange != null) {
        final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day, 0, 0, 0);
        final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59);
        query = query.gte('created_at', start.toIso8601String()).lte('created_at', end.toIso8601String());
      }

      final List<dynamic> res = await query.order('created_at', ascending: false).limit(300);

      final list = res.map((j) => KardexMovimiento.fromJson(Map<String, dynamic>.from(j))).toList();

      // Enriquecer nombres de usuario desde public.perfiles (no hay FK directa)
      final userIds = list
          .map((m) => m.usuarioId)
          .whereType<String>()
          .toSet()
          .toList();
      if (userIds.isNotEmpty) {
        try {
          final perfilesRes = await _supabase
              .from('perfiles')
              .select('id, nombre')
              .inFilter('id', userIds);
          final Map<String, String> nombresMap = {
            for (final p in perfilesRes as List)
              p['id'].toString(): (p['nombre'] ?? '').toString()
          };
          for (int i = 0; i < list.length; i++) {
            final uid = list[i].usuarioId;
            if (uid != null && nombresMap.containsKey(uid)) {
              list[i] = KardexMovimiento(
                id: list[i].id,
                productoId: list[i].productoId,
                tiendaId: list[i].tiendaId,
                tipoMovimiento: list[i].tipoMovimiento,
                origenTipo: list[i].origenTipo,
                origenId: list[i].origenId,
                cantidad: list[i].cantidad,
                costoUnitario: list[i].costoUnitario,
                stockAnterior: list[i].stockAnterior,
                stockResultante: list[i].stockResultante,
                costoMedioMomento: list[i].costoMedioMomento,
                usuarioId: uid,
                createdAt: list[i].createdAt,
                productoSku: list[i].productoSku,
                productoDescripcion: list[i].productoDescripcion,
                tiendaNombre: list[i].tiendaNombre,
                usuarioNombre: nombresMap[uid],
              );
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

  // Exportar reporte a Excel (.xlsx)
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

      // Cabeceras
      sheetObject.appendRow([
        TextCellValue('Fecha y Hora'),
        TextCellValue('SKU'),
        TextCellValue('Producto'),
        TextCellValue('Tienda'),
        TextCellValue('Tipo Movimiento'),
        TextCellValue('Origen'),
        TextCellValue('N° Documento'),
        TextCellValue('Cantidad'),
        TextCellValue('Stock Anterior'),
        TextCellValue('Stock Resultante'),
        TextCellValue('Costo Unitario (S/.)'),
        TextCellValue('Costo Medio (S/.)'),
        TextCellValue('Usuario Responsable'),
      ]);

      for (final m in _movimientos) {
        sheetObject.appendRow([
          TextCellValue(m.createdAt != null ? _fmtDate.format(m.createdAt!.toLocal()) : ''),
          TextCellValue(m.sku ?? ''),
          TextCellValue(m.descripcion_1 ?? ''),
          TextCellValue(m.tiendaNombre ?? 'General'),
          TextCellValue(m.tipoMovimiento),
          TextCellValue(m.origenTipo ?? ''),
          TextCellValue(m.origenId ?? ''),
          DoubleCellValue(m.cantidad),
          DoubleCellValue(m.stockAnterior ?? 0.0),
          DoubleCellValue(m.stockResultante ?? 0.0),
          DoubleCellValue(m.costoUnitario ?? 0.0),
          DoubleCellValue(m.costoMedioMomento ?? 0.0),
          TextCellValue(m.usuarioNombre ?? ''),
        ]);
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('No se pudo generar el archivo Excel.');
      }

      final fileName = 'Kardex_Reporte_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([fileBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
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

        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Reporte de Kardex - $fileName',
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
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                    ),
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent.shade700,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _exportarExcel,
                    icon: const Icon(Icons.file_download, size: 18),
                    label: Text(
                      esDesktop ? 'Exportar Excel' : 'Excel',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de Filtros superior
          _buildBarraFiltros(context),

          // Contenido principal
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                : _error != null
                    ? _buildErrorView()
                    : _movimientos.isEmpty
                        ? _buildEmptyView()
                        : esDesktop
                            ? _buildDesktopDataTable()
                            : _buildMobileCardsList(),
          ),
        ],
      ),
    );
  }

  // ── Barra de Filtros ──────────────────────────────────────────────────────
  Widget _buildBarraFiltros(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              // Autocompletar Buscador de Producto
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _productoSearchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Buscar Producto por SKU o Nombre...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Colors.tealAccent, size: 18),
                        suffixIcon: _buscandoProductos
                            ? const Padding(
                                padding: EdgeInsets.all(10.0),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                                ),
                              )
                            : _productoSearchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
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
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              subtitle: Text(
                                'SKU: ${p['sku'] ?? '—'}',
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedProductoId = p['id'].toString();
                                  _selectedProductoLabel = '${p['sku']} - ${p['descripcion_1']}';
                                  _productoSearchCtrl.text = _selectedProductoLabel!;
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
              const SizedBox(width: 8),

              // Selector de Tienda
              Expanded(
                flex: 2,
                child: Container(
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
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      icon: const Icon(Icons.store, color: Colors.tealAccent, size: 18),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todas las Tiendas', overflow: TextOverflow.ellipsis),
                        ),
                        ..._tiendasList.map((t) {
                          return DropdownMenuItem<int?>(
                            value: int.tryParse(t['id'].toString()),
                            child: Text(t['nombre']?.toString() ?? '', overflow: TextOverflow.ellipsis),
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
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Selector de Rango de Fechas
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                  icon: const Icon(Icons.date_range, color: Colors.tealAccent, size: 16),
                  label: Text(
                    _dateRange == null
                        ? 'Todas las Fechas'
                        : '${_fmtShortDate.format(_dateRange!.start)} - ${_fmtShortDate.format(_dateRange!.end)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_dateRange != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Limpiar Fechas',
                  icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                  onPressed: () {
                    setState(() => _dateRange = null);
                    _cargarMovimientos();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Error View ─────────────────────────────────────────────────────────────
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text('Error al cargar movimientos:\n$_error',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _cargarMovimientos,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  // ── Empty View ─────────────────────────────────────────────────────────────
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

  // ── Vista Desktop: DataTable Paginada/Con Scroll ───────────────────────────
  Widget _buildDesktopDataTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E1E1E)),
          dataRowColor: WidgetStateProperty.all(const Color(0xFF141414)),
          columnSpacing: 16,
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('Fecha y Hora', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Producto', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Tienda', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Tipo', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Origen / Doc', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Cantidad', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Stock (Ant -> Res)', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Costo Unit.', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Costo Med.', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Usuario', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
          ],
          rows: _movimientos.map((m) {
            final esEntrada = m.tipoMovimiento.toUpperCase() == 'ENTRADA';
            final esSalida = m.tipoMovimiento.toUpperCase() == 'SALIDA';

            return DataRow(
              cells: [
                DataCell(Text(
                  m.createdAt != null ? _fmtDate.format(m.createdAt!.toLocal()) : '—',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                )),
                DataCell(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(m.descripcion_1 ?? '—', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    Text('SKU: ${m.sku ?? '—'}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                )),
                DataCell(Text(m.tiendaNombre ?? 'General', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                DataCell(_buildTipoBadge(m.tipoMovimiento)),
                DataCell(Text(
                  _formatearOrigen(m.origenTipo, m.origenId),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                )),
                DataCell(Text(
                  '${esEntrada ? '+' : esSalida ? '-' : ''}${m.cantidad.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: esEntrada ? Colors.greenAccent : esSalida ? Colors.redAccent : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                )),
                DataCell(Text(
                  '${m.stockAnterior?.toStringAsFixed(0) ?? '0'} ➔ ${m.stockResultante?.toStringAsFixed(0) ?? '0'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                )),
                DataCell(Text(
                  m.costoUnitario != null ? _fmtCurrency.format(m.costoUnitario) : '—',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                )),
                DataCell(Text(
                  m.costoMedioMomento != null ? _fmtCurrency.format(m.costoMedioMomento) : '—',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                )),
                DataCell(Text(
                  m.usuarioNombre ?? 'Sistema',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Vista Móvil: Lista de Tarjetas (Cards) Vertical ────────────────────────
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
                // Top Row: Badge + Fecha
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildTipoBadge(m.tipoMovimiento),
                    Text(
                      m.createdAt != null ? _fmtDate.format(m.createdAt!.toLocal()) : '—',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Producto & SKU
                Text(
                  m.descripcion_1 ?? 'Producto sin descripción',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  'SKU: ${m.sku ?? '—'}  |  Tienda: ${m.tiendaNombre ?? 'General'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const Divider(color: Colors.white12, height: 16),

                // Cantidad y Stock
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cantidad', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Text(
                          '${esEntrada ? '+' : esSalida ? '-' : ''}${m.cantidad.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: esEntrada ? Colors.greenAccent : esSalida ? Colors.redAccent : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Stock (Ant ➔ Res)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Text(
                          '${m.stockAnterior?.toStringAsFixed(0) ?? '0'} ➔ ${m.stockResultante?.toStringAsFixed(0) ?? '0'}',
                          style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Origen, Costos y Usuario
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Doc: ${_formatearOrigen(m.origenTipo, m.origenId)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    Text(
                      'Costo: ${m.costoUnitario != null ? _fmtCurrency.format(m.costoUnitario) : '—'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
                if (m.usuarioNombre != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Responsable: ${m.usuarioNombre}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper Badge Color
  Widget _buildTipoBadge(String tipo) {
    Color bg;
    Color fg;

    switch (tipo.toUpperCase()) {
      case 'ENTRADA':
        bg = Colors.green.shade900.withValues(alpha: 0.6);
        fg = Colors.greenAccent;
        break;
      case 'SALIDA':
        bg = Colors.red.shade900.withValues(alpha: 0.6);
        fg = Colors.redAccent;
        break;
      case 'AJUSTE':
        bg = Colors.blue.shade900.withValues(alpha: 0.6);
        fg = Colors.blueAccent;
        break;
      default:
        bg = Colors.grey.shade800;
        fg = Colors.white70;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(
        tipo.toUpperCase(),
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  String _formatearOrigen(String? tipo, String? id) {
    if (tipo == null || tipo.isEmpty) return '—';
    final docId = id ?? '';
    switch (tipo.toUpperCase()) {
      case 'ORDEN_COMPRA':
        return 'Orden #$docId';
      case 'PEDIDO':
        return 'Pedido #$docId';
      case 'AJUSTE':
        return 'Ajuste #$docId';
      default:
        return '$tipo #$docId';
    }
  }
}
