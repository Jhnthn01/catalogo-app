import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/widgets/filtros_jerarquia.dart';
import 'package:catalogo_digital_app/features/inventory/conteo_toma_page.dart';

class TomaInventarioPage extends StatefulWidget {
  const TomaInventarioPage({super.key});

  @override
  State<TomaInventarioPage> createState() => _TomaInventarioPageState();
}

class _TomaInventarioPageState extends State<TomaInventarioPage> {
  final _supabase = Supabase.instance.client;

  bool _alcanceCompleto = true; // true = toda la tienda, false = filtrado
  String? _catSeleccionada;
  String? _claseSeleccionada;
  String? _subClaseSeleccionada;

  bool _isLoading = false;

  Future<void> _iniciarToma() async {
    final tiendaId = TiendaService().tiendaActivaId.value;

    if (tiendaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar una tienda activa antes de iniciar la toma de inventario.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final params = <String, dynamic>{
        'p_tienda_id': tiendaId,
        'p_categoria': _alcanceCompleto ? null : _catSeleccionada,
        'p_clase': _alcanceCompleto ? null : _claseSeleccionada,
        'p_sub_clase': _alcanceCompleto ? null : _subClaseSeleccionada,
      };

      final response = await _supabase.rpc('iniciar_toma_inventario', params: params);

      if (!mounted) return;

      String? tomaId;
      if (response is String) {
        tomaId = response;
      } else if (response is Map) {
        tomaId = response['toma_id']?.toString() ?? response['id']?.toString();
      } else if (response != null) {
        tomaId = response.toString();
      }

      if (tomaId == null || tomaId.isEmpty) {
        throw Exception('No se recibió un ID de toma válido desde el servidor.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toma de inventario iniciada correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      // Navegar a la pantalla de conteo
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConteoTomaPage(tomaId: tomaId!),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar toma de inventario: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiendaId = TiendaService().tiendaActivaId.value;
    final tiendaMap = TiendaService().tiendas.cast<Map<String, dynamic>?>().firstWhere(
      (t) => t?['id'] == tiendaId,
      orElse: () => null,
    );
    final tiendaNombre = tiendaMap?['nombre'] as String? ?? (tiendaId != null ? 'Tienda #$tiendaId' : 'Sin tienda activa');

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text(
          'Nueva Toma de Inventario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. Tarjeta de Tienda Activa ─────────────────────────────────
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: tiendaId != null ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.orangeAccent,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (tiendaId != null ? Colors.blueAccent : Colors.orangeAccent).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        color: tiendaId != null ? Colors.blueAccent : Colors.orangeAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TIENDA / SUCURSAL',
                            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tiendaNombre,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          if (tiendaId == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Selecciona una tienda en el menú superior para continuar.',
                                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── 2. Selector de Alcance ──────────────────────────────────────
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ALCANCE DE LA AUDITORÍA',
                      style: TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.all_inbox_rounded, size: 18),
                          label: Text('Toda la Tienda', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.category_rounded, size: 18),
                          label: Text('Por Categoría / Jerarquía', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                      selected: {_alcanceCompleto},
                      onSelectionChanged: (newSelection) {
                        setState(() {
                          _alcanceCompleto = newSelection.first;
                          if (_alcanceCompleto) {
                            _catSeleccionada = null;
                            _claseSeleccionada = null;
                            _subClaseSeleccionada = null;
                          }
                        });
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.blueAccent;
                          }
                          return const Color(0xFF262626);
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return Colors.white70;
                        }),
                        side: WidgetStateProperty.all(const BorderSide(color: Colors.blueAccent, width: 1.0)),
                      ),
                    ),

                    // Filtros dinámicos si no es alcance completo
                    if (!_alcanceCompleto) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 10),
                      const Text(
                        'Selecciona la categoría o subclase que se va a auditar:',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FiltrosJerarquiaWidget(
                        onFiltrosCambiados: (cat, clase, sub) {
                          setState(() {
                            _catSeleccionada = cat;
                            _claseSeleccionada = clase;
                            _subClaseSeleccionada = sub;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── 3. Resumen de la Toma ───────────────────────────────────────
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RESUMEN ANTES DE INICIAR',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    _buildFilaResumen('Tienda:', tiendaNombre),
                    _buildFilaResumen(
                      'Alcance:',
                      _alcanceCompleto
                          ? 'Todos los productos de la tienda'
                          : [
                              if (_catSeleccionada != null) 'Cat: $_catSeleccionada',
                              if (_claseSeleccionada != null) 'Clase: $_claseSeleccionada',
                              if (_subClaseSeleccionada != null) 'Sub: $_subClaseSeleccionada',
                              if (_catSeleccionada == null && _claseSeleccionada == null && _subClaseSeleccionada == null)
                                'Sin jerarquía seleccionada (General)',
                            ].join(' > '),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Al iniciar, se creará una toma en estado "conteo" congelando una instantánea del stock del sistema para comparar las cantidades contadas.',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // ── 4. Botón de Acción ──────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: (_isLoading || tiendaId == null) ? null : _iniciarToma,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  _isLoading ? 'INICIANDO TOMA...' : 'INICIAR TOMA DE INVENTARIO',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilaResumen(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
