import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';

class PedidosCanceladosPage extends StatefulWidget {
  const PedidosCanceladosPage({super.key});

  @override
  State<PedidosCanceladosPage> createState() => _PedidosCanceladosPageState();
}

class _PedidosCanceladosPageState extends State<PedidosCanceladosPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pedidos = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPedidosCancelados();
  }

  Future<void> _fetchPedidosCancelados() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final tiendaId = TiendaService().tiendaActivaId.value;

      var query = _supabase
          .from('pedidos')
          .select('''
            id,
            usuario_id,
            nombre_cliente,
            total,
            estado,
            creado_en,
            created_at,
            motivo_cancelacion,
            tipo_comprobante,
            forma_pago
          ''')
          .eq('estado', 'cancelado');

      if (tiendaId != null) {
        query = query.eq('tienda_id', tiendaId);
      }

      final response = await query.order('creado_en', ascending: false);
      final pedidos = List<Map<String, dynamic>>.from(response);

      // Obtener perfiles por usuario_id de forma independiente
      final usuarioIds = pedidos
          .map((p) => p['usuario_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> perfilesMap = {};
      if (usuarioIds.isNotEmpty) {
        final perfilesResponse = await _supabase
            .from('perfiles')
            .select('id, nombre, email')
            .inFilter('id', usuarioIds);
        for (final p in perfilesResponse) {
          perfilesMap[p['id'].toString()] = p;
        }
      }

      final merged = pedidos.map((p) {
        final uid = p['usuario_id']?.toString();
        return {
          ...p,
          'perfiles': uid != null ? perfilesMap[uid] : null,
        };
      }).toList();

      setState(() {
        _pedidos = merged;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _filterId = '';
  String _filterVendedor = '';

  @override
  Widget build(BuildContext context) {
    // Extraer vendedores únicos
    final Set<String> vendedoresSet = {};
    for (var p in _pedidos) {
      final perfiles = p['perfiles'];
      if (perfiles is Map) {
        final n = perfiles['nombre']?.toString().trim();
        final e = perfiles['email']?.toString().trim();
        if (n != null && n.isNotEmpty) {
          vendedoresSet.add(n);
        } else if (e != null && e.isNotEmpty) {
          vendedoresSet.add(e);
        }
      }
    }
    final List<String> vendedoresList = vendedoresSet.toList()..sort();

    final filteredList = _pedidos.where((p) {
      if (_filterId.trim().isNotEmpty) {
        final idStr = (p['id'] ?? '').toString().toLowerCase();
        final numCliente = (p['nombre_cliente'] ?? '').toString().toLowerCase();
        final term = _filterId.trim().toLowerCase();
        if (!idStr.contains(term) && !numCliente.contains(term)) return false;
      }
      if (_filterVendedor.trim().isNotEmpty) {
        final perfiles = p['perfiles'];
        String vend = "Sistema / Sin Asignar";
        if (perfiles is Map) {
          final n = perfiles['nombre']?.toString().trim();
          final e = perfiles['email']?.toString().trim();
          if (n != null && n.isNotEmpty) vend = n;
          else if (e != null && e.isNotEmpty) vend = e;
        }
        if (vend != _filterVendedor) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          'Pedidos Cancelados',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _fetchPedidosCancelados,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      drawer: const MenuLateral(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Error al cargar pedidos:\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchPedidosCancelados,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Barra de Filtros
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      color: const Color(0xFF1E1E1E),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              onChanged: (val) => setState(() => _filterId = val),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: "Nº Pedido / Cliente...",
                                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                                prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 18),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                filled: true,
                                fillColor: const Color(0xFF2A2A2A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _filterVendedor.isEmpty ? null : _filterVendedor,
                                  hint: const Text("Vendedor", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF2A2A2A),
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: "",
                                      child: Text("Todos vendedores", style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    ),
                                    ...vendedoresList.map((v) => DropdownMenuItem<String>(
                                          value: v,
                                          child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                        )),
                                  ],
                                  onChanged: (val) => setState(() => _filterVendedor = val ?? ""),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filteredList.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline, color: Colors.grey.shade600, size: 64),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Sin pedidos cancelados',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 18, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No hay pedidos que coincidan con la búsqueda.',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchPedidosCancelados,
                              color: Colors.redAccent,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(15),
                                itemCount: filteredList.length,
                                itemBuilder: (context, index) {
                                  final p = filteredList[index];
                                  return _PedidoCanceladoCard(pedido: p);
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _PedidoCanceladoCard extends StatelessWidget {
  final Map<String, dynamic> pedido;
  const _PedidoCanceladoCard({required this.pedido});

  @override
  Widget build(BuildContext context) {
    final String idCorto = pedido['id'].toString().substring(0, 8).toUpperCase();
    final String cliente = pedido['nombre_cliente'] ?? 'Cliente no especificado';
    final double total = double.tryParse((pedido['total'] ?? 0).toString()) ?? 0.0;
    final String? motivo = pedido['motivo_cancelacion'] as String?;
    final DateTime fecha = DateTime.parse(
      pedido['creado_en'] ?? pedido['created_at'],
    ).toLocal();
    final String fechaStr = DateFormat('dd/MM/yyyy – hh:mm a').format(fecha);

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.35), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido #$idCorto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fechaStr,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    'CANCELADO',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 10),

            // Cliente & Total
            Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.grey, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cliente,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.badge_outlined, color: Colors.blueAccent, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Vendedor: ${pedido['perfiles'] != null && (pedido['perfiles']['nombre']?.toString().trim().isNotEmpty ?? false) ? pedido['perfiles']['nombre'] : (pedido['perfiles']?['email'] ?? 'Sistema / Sin Asignar')}",
                    style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.monetization_on_outlined, color: Colors.grey, size: 15),
                const SizedBox(width: 6),
                Text(
                  'Total: S/.${total.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Motivo de cancelación — prominente
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.redAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'MOTIVO DE CANCELACIÓN',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    motivo != null && motivo.isNotEmpty
                        ? motivo
                        : 'Sin motivo registrado.',
                    style: TextStyle(
                      color: motivo != null && motivo.isNotEmpty
                          ? Colors.white70
                          : Colors.grey.shade600,
                      fontSize: 13,
                      fontStyle: motivo == null || motivo.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
