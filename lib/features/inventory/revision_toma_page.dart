import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class RevisionTomaPage extends StatefulWidget {
  final String tomaId;

  const RevisionTomaPage({super.key, required this.tomaId});

  @override
  State<RevisionTomaPage> createState() => _RevisionTomaPageState();
}

class _RevisionTomaPageState extends State<RevisionTomaPage> {
  final _supabase = Supabase.instance.client;
  static final NumberFormat _monedaFmt = NumberFormat.currency(symbol: 'S/. ', decimalDigits: 2);

  bool _isLoading = true;
  bool _isApproving = false;

  Map<String, dynamic>? _tomaHeader;
  List<Map<String, dynamic>> _lineasDiscrepancias = [];

  String _searchFilter = '';
  String _tipoFilter = 'todos'; // 'todos' | 'faltantes' | 'sobrantes'

  // Métricas agregadas
  double _impactoNeto = 0.0;
  double _montoFaltantes = 0.0;
  double _montoSobrantes = 0.0;
  int _unidadesFaltantes = 0;
  int _unidadesSobrantes = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatosToma();
  }

  Future<void> _cargarDatosToma() async {
    setState(() => _isLoading = true);

    try {
      // 1. Cabecera de la toma
      final headerRes = await _supabase
          .from('tomas_inventario')
          .select('id, tienda_id, estado, creado_en, cerrado_en, aplicado_en, alcance_categoria, alcance_clase, tiendas(nombre)')
          .eq('id', widget.tomaId)
          .maybeSingle();

      if (headerRes != null) {
        _tomaHeader = Map<String, dynamic>.from(headerRes);
      }

      // 2. Líneas con discrepancias (diferencia IS NOT NULL AND diferencia != 0)
      final List<dynamic> detallesRes = await _supabase
          .from('tomas_inventario_detalle')
          .select(
            'id, toma_id, producto_id, stock_sistema, cantidad_contada, diferencia, contado_en, '
            'productos(id, sku, upc, alu, descripcion_1, marca, color, costo_medio, costo, precio_venta)',
          )
          .eq('toma_id', widget.tomaId)
          .not('diferencia', 'is', null)
          .neq('diferencia', 0);

      final List<Map<String, dynamic>> lineas = [];
      double impactoNeto = 0.0;
      double montoFaltantes = 0.0;
      double montoSobrantes = 0.0;
      int unidadesFaltantes = 0;
      int unidadesSobrantes = 0;

      for (final raw in detallesRes) {
        if (raw is Map) {
          final item = Map<String, dynamic>.from(raw);
          final prod = item['productos'] is Map ? item['productos'] as Map : {};
          final diferencia = (item['diferencia'] as num?)?.toInt() ?? 0;

          // Determinar costo unitario base (prioriza costo_medio)
          double costoUnitario = double.tryParse(prod['costo_medio']?.toString() ?? '') ?? 0.0;
          if (costoUnitario <= 0) {
            costoUnitario = double.tryParse(prod['costo']?.toString() ?? '') ?? 0.0;
          }

          final double impacto = diferencia * costoUnitario;
          final double impactoAbs = impacto.abs();

          item['costo_unitario_calc'] = costoUnitario;
          item['impacto_calc'] = impacto;
          item['impacto_abs'] = impactoAbs;

          lineas.add(item);

          impactoNeto += impacto;
          if (diferencia < 0) {
            unidadesFaltantes += diferencia.abs();
            montoFaltantes += impacto.abs();
          } else if (diferencia > 0) {
            unidadesSobrantes += diferencia;
            montoSobrantes += impacto;
          }
        }
      }

      // 3. Ordenar por mayor impacto económico absoluto descendente
      lineas.sort((a, b) {
        final double impA = (a['impacto_abs'] as num?)?.toDouble() ?? 0.0;
        final double impB = (b['impacto_abs'] as num?)?.toDouble() ?? 0.0;
        return impB.compareTo(impA);
      });

      if (!mounted) return;

      setState(() {
        _lineasDiscrepancias = lineas;
        _impactoNeto = impactoNeto;
        _montoFaltantes = montoFaltantes;
        _montoSobrantes = montoSobrantes;
        _unidadesFaltantes = unidadesFaltantes;
        _unidadesSobrantes = unidadesSobrantes;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar revisión de toma: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _aprobarYAplicarToma() async {
    final estadoActual = _tomaHeader?['estado']?.toString().toLowerCase();

    if (estadoActual == 'aplicada') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta toma de inventario ya fue aplicada anteriormente.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Colors.blueAccent, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '¿Aprobar y Aplicar Ajustes?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta acción aplicará los ajustes definitivos en el inventario y generará los movimientos correspondientes en el Kardex:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  _buildFilaModal('Líneas a ajustar:', '${_lineasDiscrepancias.length} productos'),
                  _buildFilaModal('Faltantes:', '-$_unidadesFaltantes und. (${_monedaFmt.format(_montoFaltantes)})'),
                  _buildFilaModal('Sobrantes:', '+$_unidadesSobrantes und. (${_monedaFmt.format(_montoSobrantes)})'),
                  const Divider(color: Colors.white12),
                  _buildFilaModal(
                    'Impacto Neto:',
                    _monedaFmt.format(_impactoNeto),
                    valorColor: _impactoNeto < 0 ? Colors.redAccent : Colors.greenAccent,
                    bold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Una vez aplicada, la toma no podrá ser modificada ni recalculada.',
              style: TextStyle(color: Colors.amberAccent, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprobar y Aplicar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _isApproving = true);

    try {
      await _supabase.rpc('aprobar_toma_inventario', params: {
        'p_toma_id': widget.tomaId,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Toma de inventario aprobada y stock aplicado exitosamente!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        String mensajeError = e.toString();
        // Limpiar prefijo común de excepciones de Supabase/PostgREST
        if (mensajeError.contains('PostgrestException')) {
          mensajeError = mensajeError.replaceAll(RegExp(r'PostgrestException\(message:\s*'), '').replaceAll(RegExp(r',.*'), '');
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.redAccent),
            ),
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('No se pudo aprobar la toma', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              mensajeError,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido', style: TextStyle(color: Colors.blueAccent)),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  Widget _buildFilaModal(String label, String valor, {Color valorColor = Colors.white, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(
            valor,
            style: TextStyle(color: valorColor, fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.w500),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _lineasFiltradas {
    return _lineasDiscrepancias.where((item) {
      final diferencia = (item['diferencia'] as num?)?.toInt() ?? 0;
      if (_tipoFilter == 'faltantes' && diferencia >= 0) return false;
      if (_tipoFilter == 'sobrantes' && diferencia <= 0) return false;

      if (_searchFilter.isNotEmpty) {
        final prod = item['productos'] is Map ? item['productos'] as Map : {};
        final sku = (prod['sku'] ?? '').toString().toLowerCase();
        final nombre = (prod['descripcion_1'] ?? '').toString().toLowerCase();
        final q = _searchFilter.toLowerCase();
        if (!sku.contains(q) && !nombre.contains(q)) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final estado = _tomaHeader?['estado']?.toString().toLowerCase() ?? 'conteo';
    final tiendaNombre = _tomaHeader?['tiendas']?['nombre'] ?? 'Tienda';
    final bool puedeAprobar = estado == 'pendiente_aprobacion' || estado == 'conteo';

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revisión y Ajuste de Inventario',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '$tiendaNombre • Toma: ${widget.tomaId.substring(0, 8)}...',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          _buildEstadoBadge(estado),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Recargar discrepancias',
            onPressed: _cargarDatosToma,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── 1. Tarjetas de Métricas Económicas ─────────────
                        _buildSeccionMetricas(),
                        const SizedBox(height: 16),

                        // ── 2. Barra de Filtros y Búsqueda ─────────────────
                        _buildBarraFiltros(),
                        const SizedBox(height: 14),

                        // ── 3. Listado de Discrepancias ────────────────────
                        _buildListaDiscrepancias(),
                      ],
                    ),
                  ),
                ),

                // ── 4. Barra Inferior de Acción ────────────────────────────
                _buildBarraInferior(puedeAprobar, estado),
              ],
            ),
    );
  }

  Widget _buildEstadoBadge(String estado) {
    Color color;
    String texto;
    switch (estado) {
      case 'aplicada':
        color = Colors.greenAccent;
        texto = 'APLICADA';
        break;
      case 'pendiente_aprobacion':
        color = Colors.amberAccent;
        texto = 'POR APROBAR';
        break;
      case 'cancelada':
        color = Colors.redAccent;
        texto = 'CANCELADA';
        break;
      default:
        color = Colors.blueAccent;
        texto = 'EN CONTEO';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSeccionMetricas() {
    return Column(
      children: [
        // Tarjeta Principal: Impacto Neto
        Card(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _impactoNeto < 0 ? Colors.redAccent.withValues(alpha: 0.4) : Colors.greenAccent.withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_impactoNeto < 0 ? Colors.redAccent : Colors.greenAccent).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _impactoNeto < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                    color: _impactoNeto < 0 ? Colors.redAccent : Colors.greenAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IMPACTO ECONÓMICO NETO',
                        style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _monedaFmt.format(_impactoNeto),
                        style: TextStyle(
                          color: _impactoNeto < 0 ? Colors.redAccent : Colors.greenAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Total de ${_lineasDiscrepancias.length} productos con diferencias',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Desglose: Faltantes vs Sobrantes
        Row(
          children: [
            Expanded(
              child: _buildMiniCardMetrica(
                titulo: 'FALTANTES (PÉRDIDA)',
                unidades: '-$_unidadesFaltantes und.',
                monto: _monedaFmt.format(_montoFaltantes),
                color: Colors.redAccent,
                icon: Icons.remove_circle_outline_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniCardMetrica(
                titulo: 'SOBRANTES (EXCEDENTE)',
                unidades: '+$_unidadesSobrantes und.',
                monto: _monedaFmt.format(_montoSobrantes),
                color: Colors.greenAccent,
                icon: Icons.add_circle_outline_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniCardMetrica({
    required String titulo,
    required String unidades,
    required String monto,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              monto,
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              unidades,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraFiltros() {
    return Column(
      children: [
        // Buscador local
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Filtrar por SKU o nombre...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 18),
              suffixIcon: _searchFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                      onPressed: () => setState(() => _searchFilter = ''),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (val) => setState(() => _searchFilter = val.trim()),
          ),
        ),
        const SizedBox(height: 8),

        // Filtro por tipo (Segmented)
        SegmentedButton<String>(
          segments: [
            ButtonSegment<String>(
              value: 'todos',
              label: Text('Todos (${_lineasDiscrepancias.length})', style: const TextStyle(fontSize: 11)),
            ),
            const ButtonSegment<String>(
              value: 'faltantes',
              label: Text('Solo Faltantes (-)', style: TextStyle(fontSize: 11)),
            ),
            const ButtonSegment<String>(
              value: 'sobrantes',
              label: Text('Solo Sobrantes (+)', style: TextStyle(fontSize: 11)),
            ),
          ],
          selected: {_tipoFilter},
          onSelectionChanged: (newSelection) {
            setState(() => _tipoFilter = newSelection.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.blueAccent;
              }
              return const Color(0xFF1E1E1E);
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return Colors.white70;
            }),
            side: WidgetStateProperty.all(const BorderSide(color: Colors.white12)),
          ),
        ),
      ],
    );
  }

  Widget _buildListaDiscrepancias() {
    final filtradas = _lineasFiltradas;

    if (filtradas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            const Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              '¡Sin discrepancias encontradas!',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _searchFilter.isNotEmpty
                  ? 'No hay resultados que coincidan con "$_searchFilter".'
                  : 'Todos los productos contados coinciden exactamente con el stock del sistema.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DISCREPANCIAS ORDENADAS POR IMPACTO (${filtradas.length})',
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            const Text(
              'Mayor impacto arriba',
              style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtradas.length,
          itemBuilder: (context, index) {
            final item = filtradas[index];
            final prod = item['productos'] is Map ? item['productos'] as Map : {};
            final diferencia = (item['diferencia'] as num?)?.toInt() ?? 0;
            final stockSistema = (item['stock_sistema'] as num?)?.toInt() ?? 0;
            final cantidadContada = (item['cantidad_contada'] as num?)?.toInt() ?? 0;
            final costoUnit = (item['costo_unitario_calc'] as num?)?.toDouble() ?? 0.0;
            final impacto = (item['impacto_calc'] as num?)?.toDouble() ?? 0.0;

            final bool esFaltante = diferencia < 0;
            final Color colorDiff = esFaltante ? Colors.redAccent : Colors.greenAccent;

            return Card(
              color: const Color(0xFF1E1E1E),
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorDiff.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fila 1: SKU y Nombre
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            prod['sku'] ?? '—',
                            style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            prod['descripcion_1'] ?? 'Producto #${item['producto_id']}',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 10),

                    // Fila 2: Tabla de Cantidades e Impacto
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDatoColumna('Stock Sistema', '$stockSistema und.'),
                        _buildDatoColumna('Físico Contado', '$cantidadContada und.'),
                        _buildBadgeDiferencia(diferencia, colorDiff),
                        _buildDatoColumna(
                          'Impacto',
                          _monedaFmt.format(impacto),
                          valorColor: colorDiff,
                          bold: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Costo unit. base: ${_monedaFmt.format(costoUnit)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDatoColumna(String label, String valor, {Color valorColor = Colors.white, bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(color: valorColor, fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildBadgeDiferencia(int diferencia, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Diferencia', style: TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            '${diferencia > 0 ? '+' : ''}$diferencia und.',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildBarraInferior(bool puedeAprobar, String estado) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: puedeAprobar ? Colors.blueAccent : Colors.grey.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: (_isApproving || !puedeAprobar) ? null : _aprobarYAplicarToma,
            icon: _isApproving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(puedeAprobar ? Icons.check_circle_rounded : Icons.lock_rounded, size: 22),
            label: Text(
              _isApproving
                  ? 'APLICANDO AJUSTES...'
                  : (estado == 'aplicada'
                      ? 'TOMA YA APLICADA'
                      : (estado == 'cancelada' ? 'TOMA CANCELADA' : 'APROBAR Y APLICAR AJUSTE')),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}
