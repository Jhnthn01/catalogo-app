import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'crear_orden_compra_screen.dart';
import 'recepcion_orden_compra_screen.dart';

class OrdenesCompraDashboardScreen extends StatefulWidget {
  const OrdenesCompraDashboardScreen({super.key});

  @override
  State<OrdenesCompraDashboardScreen> createState() =>
      _OrdenesCompraDashboardScreenState();
}

class _OrdenesCompraDashboardScreenState
    extends State<OrdenesCompraDashboardScreen> {
  // Formatters sin locale → no requieren initializeDateFormatting
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  static final NumberFormat _currencyFmt =
      NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  late Future<List<Map<String, dynamic>>> _ordenesFuture;

  @override
  void initState() {
    super.initState();
    _ordenesFuture = _fetchOrdenes();
  }

  Future<List<Map<String, dynamic>>> _fetchOrdenes() async {
    final response = await Supabase.instance.client
        .from('ordenes_compra')
        .select('*, proveedores(razon_social)')
        .order('fecha_orden', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }

  void _recargar() {
    setState(() {
      _ordenesFuture = _fetchOrdenes();
    });
  }

  // ── Estado → color de fondo ──────────────────────────────────────────────
  Color _bgEstado(String? estado) {
    switch (estado) {
      case 'borrador':
        return Colors.grey.shade700;
      case 'enviada':
        return Colors.blue.shade700;
      case 'recibida_parcial':
        return Colors.orange.shade700;
      case 'recibida_completa':
        return Colors.green.shade700;
      case 'cancelada':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade800;
    }
  }

  // ── Estado → etiqueta legible ────────────────────────────────────────────
  String _labelEstado(String? estado) {
    switch (estado) {
      case 'borrador':
        return 'Borrador';
      case 'enviada':
        return 'Enviada';
      case 'recibida_parcial':
        return 'Recibida parcial';
      case 'recibida_completa':
        return 'Recibida completa';
      case 'cancelada':
        return 'Cancelada';
      default:
        return estado ?? 'Desconocido';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Abastecimiento',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Recargar',
            onPressed: _recargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent.shade400,
        foregroundColor: Colors.black,
        tooltip: 'Nueva Orden',
        onPressed: () async {
          final resultado = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => const CrearOrdenCompraScreen(),
            ),
          );
          // Si se guardó con éxito, recarga el listado
          if (resultado == true) {
            _recargar();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ordenesFuture,
        builder: (context, snapshot) {
          // ── Cargando ─────────────────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            );
          }

          // ── Error ────────────────────────────────────────────────────────
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 48),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Error al cargar las órdenes:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _recargar,
                    icon: const Icon(Icons.refresh, color: Colors.tealAccent),
                    label: const Text('Reintentar',
                        style: TextStyle(color: Colors.tealAccent)),
                  ),
                ],
              ),
            );
          }

          // ── Sin datos ────────────────────────────────────────────────────
          final ordenes = snapshot.data ?? [];
          if (ordenes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined,
                      size: 72,
                      color: Colors.tealAccent.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text(
                    'Sin órdenes de compra',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Presiona + para crear la primera',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          // ── Lista de órdenes ─────────────────────────────────────────────
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: ordenes.length,
            itemBuilder: (context, index) {
              final orden = ordenes[index];

              final proveedor =
                  (orden['proveedores'] as Map<String, dynamic>?)?['razon_social']
                      as String? ??
                  'Proveedor desconocido';

              final estado = orden['estado'] as String?;

              // Fecha
              String fechaStr = '—';
              final rawFecha = orden['fecha_orden'];
              if (rawFecha != null) {
                try {
                  final fecha = DateTime.parse(rawFecha.toString()).toLocal();
                  fechaStr = _dateFmt.format(fecha);
                } catch (_) {}
              }

              // Monto
              String montoStr = '—';
              final rawMonto = orden['monto_total'];
              if (rawMonto != null) {
                try {
                  montoStr =
                      _currencyFmt.format(double.parse(rawMonto.toString()));
                } catch (_) {}
              }

              final bool puedeRecepcionar =
                  estado == 'enviada' || estado == 'recibida_parcial';

              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: puedeRecepcionar
                        ? Colors.tealAccent.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: CircleAvatar(
                    backgroundColor:
                        Colors.tealAccent.withValues(alpha: 0.12),
                    child: const Icon(Icons.local_shipping,
                        color: Colors.tealAccent, size: 22),
                  ),
                  title: Text(
                    proveedor,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 12, color: Colors.white38),
                        const SizedBox(width: 4),
                        Text(
                          fechaStr,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        if (puedeRecepcionar) ...[  
                          const SizedBox(width: 8),
                          const Icon(Icons.touch_app,
                              size: 12, color: Colors.tealAccent),
                          const Text(
                            ' Recepcionar',
                            style: TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        montoStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _bgEstado(estado),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _labelEstado(estado),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: puedeRecepcionar
                      ? () async {
                          final resultado =
                              await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  RecepcionOrdenCompraScreen(
                                ordenId: orden['id'].toString(),
                              ),
                            ),
                          );
                          if (resultado == true) _recargar();
                        }
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
