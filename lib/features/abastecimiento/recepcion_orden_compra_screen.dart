import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de fila de detalle
// ─────────────────────────────────────────────────────────────────────────────
class _DetalleItem {
  final String detalleId;
  final String productoId;
  final String descripcion;
  final String sku;
  final double cantidadSolicitada;
  final double cantidadRecibidaAnterior;
  final double costoUnitario;
  final TextEditingController ingresoCtrl;

  _DetalleItem({
    required this.detalleId,
    required this.productoId,
    required this.descripcion,
    required this.sku,
    required this.cantidadSolicitada,
    required this.cantidadRecibidaAnterior,
    this.costoUnitario = 0.0,
  }) : ingresoCtrl = TextEditingController(text: '0');

  void dispose() => ingresoCtrl.dispose();

  double get ingresoHoy => double.tryParse(ingresoCtrl.text) ?? 0;
  double get totalRecibido => cantidadRecibidaAnterior + ingresoHoy;
  bool get completo => totalRecibido >= cantidadSolicitada;
}

// ─────────────────────────────────────────────────────────────────────────────
class RecepcionOrdenCompraScreen extends StatefulWidget {
  final String ordenId;

  const RecepcionOrdenCompraScreen({super.key, required this.ordenId});

  @override
  State<RecepcionOrdenCompraScreen> createState() =>
      _RecepcionOrdenCompraScreenState();
}

class _RecepcionOrdenCompraScreenState
    extends State<RecepcionOrdenCompraScreen> {
  static final NumberFormat _fmt =
      NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  static final NumberFormat _cantFmt = NumberFormat('#,##0.##');

  bool _cargando = true;
  String? _error;
  List<_DetalleItem> _items = [];

  // Datos de cabecera de la orden
  String _proveedorNombre = '';
  String _estadoActual = '';

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDetalles();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDetalles() async {
    try {
      // Cabecera de la orden
      final ordenResp = await Supabase.instance.client
          .from('ordenes_compra')
          .select('estado, proveedores(razon_social)')
          .eq('id', widget.ordenId)
          .single();

      // Detalles con JOIN a productos
      final detallesResp = await Supabase.instance.client
          .from('detalles_orden_compra')
          .select('id, producto_id, cantidad, cantidad_recibida, costo_unitario, productos(descripcion_1, sku)')
          .eq('orden_compra_id', widget.ordenId);

      if (!mounted) return;

      final detallesList =
          List<Map<String, dynamic>>.from(detallesResp as List);

      setState(() {
        _proveedorNombre =
            (ordenResp['proveedores'] as Map<String, dynamic>?)?['razon_social']
                as String? ??
            '—';
        _estadoActual = ordenResp['estado'] as String? ?? '';

        _items = detallesList.map((d) {
          final prod = d['productos'] as Map<String, dynamic>? ?? {};
          return _DetalleItem(
            detalleId: d['id'].toString(),
            productoId: d['producto_id'].toString(),
            descripcion: prod['descripcion_1'] as String? ?? 'Sin descripción',
            sku: prod['sku'] as String? ?? '—',
            cantidadSolicitada:
                double.tryParse(d['cantidad'].toString()) ?? 0,
            cantidadRecibidaAnterior:
                double.tryParse(d['cantidad_recibida']?.toString() ?? '0') ??
                    0,
            costoUnitario:
                double.tryParse(d['costo_unitario']?.toString() ?? '0') ?? 0.0,
          );
        }).toList();

        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  // ── Registrar ingreso físico ─────────────────────────────────────────────
  Future<void> _registrarIngreso() async {
    // Validar que al menos un campo tenga ingreso > 0
    final hayIngreso = _items.any((i) => i.ingresoHoy > 0);
    if (!hayIngreso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa al menos una cantidad mayor a 0'),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      // 1. Actualizar cada detalle sumando el ingreso de hoy y actualizar ultimo_costo del producto
      for (final item in _items) {
        if (item.ingresoHoy <= 0) continue;
        final nuevaCantRecibida = item.cantidadRecibidaAnterior + item.ingresoHoy;
        await Supabase.instance.client
            .from('detalles_orden_compra')
            .update({'cantidad_recibida': nuevaCantRecibida})
            .eq('id', item.detalleId);

        if (item.costoUnitario > 0) {
          await Supabase.instance.client
              .from('productos')
              .update({'ultimo_costo': item.costoUnitario})
              .eq('id', item.productoId);
        }
      }

      // 2. Re-leer el estado actualizado de todos los detalles para determinar el estado de la orden
      final detallesActualizados = await Supabase.instance.client
          .from('detalles_orden_compra')
          .select('cantidad, cantidad_recibida')
          .eq('orden_compra_id', widget.ordenId);

      final lista =
          List<Map<String, dynamic>>.from(detallesActualizados as List);

      final todosCompletos = lista.every((d) {
        final sol = double.tryParse(d['cantidad'].toString()) ?? 0;
        final rec =
            double.tryParse(d['cantidad_recibida']?.toString() ?? '0') ?? 0;
        return rec >= sol;
      });

      final nuevoEstado =
          todosCompletos ? 'recibida_completa' : 'recibida_parcial';

      // 3. Actualizar estado de la orden
      await Supabase.instance.client
          .from('ordenes_compra')
          .update({'estado': nuevoEstado})
          .eq('id', widget.ordenId);

      if (!mounted) return;

      final msg = todosCompletos
          ? '✅ Recepción completa. Orden cerrada.'
          : '📦 Ingreso parcial registrado.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              todosCompletos ? Colors.green.shade700 : Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true); // true = recargar dashboard
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recepción de Mercancía',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            if (_proveedorNombre.isNotEmpty)
              Text(
                _proveedorNombre,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (!_cargando && _error == null)
            _guardando
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.tealAccent),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _registrarIngreso,
                    icon: const Icon(Icons.check_circle_outline,
                        color: Colors.tealAccent, size: 18),
                    label: const Text(
                      'Registrar',
                      style: TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent))
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Error al cargar la orden:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _cargando = true;
                _error = null;
              });
              _cargarDetalles();
            },
            icon: const Icon(Icons.refresh, color: Colors.tealAccent),
            label: const Text('Reintentar',
                style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
  }

  // ── Cuerpo principal ─────────────────────────────────────────────────────
  Widget _buildBody() {
    return Column(
      children: [
        // Banner de estado actual
        _buildBannerEstado(),

        // Lista de productos
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            itemCount: _items.length,
            itemBuilder: (context, index) =>
                _buildItemDetalle(_items[index]),
          ),
        ),

        // Botón inferior de confirmación
        _buildBotonConfirmar(),
      ],
    );
  }

  // ── Banner de estado ─────────────────────────────────────────────────────
  Widget _buildBannerEstado() {
    Color color;
    String label;
    IconData icon;

    switch (_estadoActual) {
      case 'enviada':
        color = Colors.blue.shade700;
        label = 'Enviada — pendiente de recepción';
        icon = Icons.local_shipping_outlined;
        break;
      case 'recibida_parcial':
        color = Colors.orange.shade700;
        label = 'Recepción parcial — faltan artículos';
        icon = Icons.inventory_2_outlined;
        break;
      default:
        color = Colors.grey.shade700;
        label = _estadoActual;
        icon = Icons.info_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.25),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de detalle ───────────────────────────────────────────────────
  Widget _buildItemDetalle(_DetalleItem item) {
    final pendiente =
        (item.cantidadSolicitada - item.cantidadRecibidaAnterior)
            .clamp(0, double.infinity);
    final estaCompleto =
        item.cantidadRecibidaAnterior >= item.cantidadSolicitada;

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: estaCompleto
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre y SKU
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.descripcion,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (estaCompleto)
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 18),
              ],
            ),
            Text(
              'SKU: ${item.sku}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 10),

            // Fila de cantidades
            Row(
              children: [
                _cantidadChip(
                  'Solicitado',
                  _cantFmt.format(item.cantidadSolicitada),
                  Colors.white38,
                ),
                const SizedBox(width: 8),
                _cantidadChip(
                  'Ya recibido',
                  _cantFmt.format(item.cantidadRecibidaAnterior),
                  item.cantidadRecibidaAnterior > 0
                      ? Colors.orange.shade300
                      : Colors.white38,
                ),
                const SizedBox(width: 8),
                _cantidadChip(
                  'Pendiente',
                  _cantFmt.format(pendiente),
                  pendiente > 0 ? Colors.redAccent : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Campo "Ingresa hoy"
            if (!estaCompleto)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: item.ingresoCtrl,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Ingresa hoy',
                        labelStyle:
                            const TextStyle(color: Colors.tealAccent),
                        hintText: '0',
                        hintStyle:
                            const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Colors.tealAccent, width: 1.5),
                        ),
                        suffixText: 'uds',
                        suffixStyle:
                            const TextStyle(color: Colors.white38),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Preview nuevo total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Nuevo total',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 10)),
                      Text(
                        _cantFmt.format(item.totalRecibido),
                        style: TextStyle(
                          color: item.completo
                              ? Colors.greenAccent
                              : Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '✅ Cantidad completa recibida',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Chip de cantidad ─────────────────────────────────────────────────────
  Widget _cantidadChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Botón inferior de confirmación ───────────────────────────────────────
  Widget _buildBotonConfirmar() {
    final hayIngreso = _items.any((i) => i.ingresoHoy > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: hayIngreso
                ? Colors.tealAccent.shade400
                : Colors.grey.shade800,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: (_guardando || !hayIngreso) ? null : _registrarIngreso,
          icon: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black54),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(
            _guardando ? 'Registrando…' : 'Registrar Ingreso Físico',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
