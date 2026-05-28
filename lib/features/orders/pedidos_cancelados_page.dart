import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';

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
      final response = await _supabase
          .from('pedidos')
          .select('''
            id,
            nombre_cliente,
            total,
            estado,
            creado_en,
            created_at,
            motivo_cancelacion,
            tipo_comprobante,
            forma_pago
          ''')
          .eq('estado', 'cancelado')
          .order('creado_en', ascending: false);

      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              : _pedidos.isEmpty
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
                            'No hay pedidos con estado cancelado.',
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
                        itemCount: _pedidos.length,
                        itemBuilder: (context, index) {
                          final p = _pedidos[index];
                          return _PedidoCanceladoCard(pedido: p);
                        },
                      ),
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
