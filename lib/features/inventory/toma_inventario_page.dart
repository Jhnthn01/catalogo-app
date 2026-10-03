import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/services/toma_inventario_service.dart';
import 'package:catalogo_digital_app/widgets/filtros_jerarquia.dart';
import 'package:catalogo_digital_app/widgets/toma_progreso_card.dart';
import 'package:catalogo_digital_app/features/inventory/conteo_toma_page.dart';
import 'package:catalogo_digital_app/features/inventory/revision_toma_page.dart';

class TomaInventarioPage extends StatefulWidget {
  const TomaInventarioPage({super.key});

  @override
  State<TomaInventarioPage> createState() => _TomaInventarioPageState();
}

class _TomaInventarioPageState extends State<TomaInventarioPage> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  late TabController _tabController;

  bool _alcanceCompleto = true; // true = toda la tienda, false = filtrado
  String? _catSeleccionada;
  String? _claseSeleccionada;
  String? _subClaseSeleccionada;

  bool _isLoading = false;
  bool _isLoadingHistorial = false;
  List<Map<String, dynamic>> _historialTomas = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarHistorial();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    setState(() => _isLoadingHistorial = true);
    try {
      final List<dynamic> data = await _supabase
          .from('tomas_inventario')
          .select('id, tienda_id, estado, creado_en, cerrado_en, aplicado_en, alcance_categoria, alcance_clase, alcance_sub_clase, tiendas(nombre)')
          .order('creado_en', ascending: false)
          .limit(40);

      if (!mounted) return;
      setState(() {
        _historialTomas = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('Error al cargar historial de tomas: $e');
    } finally {
      if (mounted) setState(() => _isLoadingHistorial = false);
    }
  }

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

      final tiendaMap = TiendaService().tiendas.cast<Map<String, dynamic>?>().firstWhere(
        (t) => t?['id'] == tiendaId,
        orElse: () => null,
      );
      final tiendaNombre = tiendaMap?['nombre'] as String? ?? 'Tienda #$tiendaId';

      final alcanceStr = _alcanceCompleto
          ? 'Toda la Tienda'
          : [
              if (_catSeleccionada != null) 'Cat: $_catSeleccionada',
              if (_claseSeleccionada != null) 'Clase: $_claseSeleccionada',
              if (_subClaseSeleccionada != null) 'Sub: $_subClaseSeleccionada',
            ].join(' > ');

      TomaInventarioService().iniciarSesion(
        tomaId: tomaId,
        tiendaId: tiendaId,
        tiendaNombre: tiendaNombre,
        alcanceTexto: alcanceStr.isEmpty ? 'Por Jerarquía' : alcanceStr,
        categoria: _catSeleccionada,
        clase: _claseSeleccionada,
        subClase: _subClaseSeleccionada,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toma de inventario iniciada correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      // Navegar a la pantalla de conteo
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConteoTomaPage(tomaId: tomaId!),
        ),
      );

      _cargarHistorial();
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

  /// Elimina una toma que está en estado 'conteo' y no tiene productos contados.
  Future<void> _eliminarToma(String tomaId) async {
    // Verificar que no tenga conteos registrados
    try {
      final List<dynamic> conteos = await _supabase
          .from('tomas_inventario_detalle')
          .select('id')
          .eq('toma_id', tomaId)
          .not('cantidad_contada', 'is', null)
          .limit(1);

      if (!mounted) return;

      if (conteos.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se puede eliminar: esta toma ya tiene productos contados. Cancélala desde la pantalla de revisión.'),
            backgroundColor: Colors.orangeAccent,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Error al verificar conteos: $e');
    }

    // Confirmar eliminación
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
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Eliminar toma vacía',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Esta toma no tiene ningún producto contado.\n\n¿Deseas eliminarla del historial?',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      // Eliminar primero los detalles (aunque estén vacíos, por FK)
      await _supabase
          .from('tomas_inventario_detalle')
          .delete()
          .eq('toma_id', tomaId);

      // Eliminar la toma principal
      await _supabase
          .from('tomas_inventario')
          .delete()
          .eq('id', tomaId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toma eliminada del historial.'),
          backgroundColor: Colors.green,
        ),
      );

      _cargarHistorial();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar toma: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int pendientesCount = _historialTomas
        .where((t) => t['estado']?.toString().toLowerCase() == 'pendiente_aprobacion')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text(
          'Toma de Inventario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white60,
          tabs: [
            const Tab(
              icon: Icon(Icons.add_task_rounded, size: 20),
              text: 'Nueva Toma',
            ),
            Tab(
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history_rounded, size: 20),
                  if (pendientesCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendientesCount',
                        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              text: 'Historial / Revisiones',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── TAB 1: FORMULARIO NUEVA TOMA ──────────────────────────────────
          _buildTabNuevaToma(),

          // ── TAB 2: HISTORIAL Y REVISIONES ─────────────────────────────────
          _buildTabHistorial(),
        ],
      ),
    );
  }

  Widget _buildTabNuevaToma() {
    final tiendaId = TiendaService().tiendaActivaId.value;
    final tiendaMap = TiendaService().tiendas.cast<Map<String, dynamic>?>().firstWhere(
      (t) => t?['id'] == tiendaId,
      orElse: () => null,
    );
    final tiendaNombre = tiendaMap?['nombre'] as String? ?? (tiendaId != null ? 'Tienda #$tiendaId' : 'Sin tienda activa');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 0. Tarjeta de Toma Activa si existe en memoria ───────────────
          const TomaProgresoCard(
            margin: EdgeInsets.only(bottom: 20),
          ),

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
                          'Al iniciar, se creará una toma congelando una instantánea del stock del sistema para comparar las cantidades contadas.',
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
    );
  }

  Widget _buildTabHistorial() {
    if (_isLoadingHistorial) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.tealAccent),
      );
    }

    if (_historialTomas.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargarHistorial,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.checklist_rtl_rounded, color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              const Text(
                'No hay tomas de inventario registradas',
                style: TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _cargarHistorial,
                icon: const Icon(Icons.refresh, color: Colors.tealAccent),
                label: const Text('Refrescar', style: TextStyle(color: Colors.tealAccent)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarHistorial,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _historialTomas.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final t = _historialTomas[index];
          final String tomaId = t['id']?.toString() ?? '';
          final String estado = (t['estado']?.toString() ?? 'en_proceso').toLowerCase();
          final tiendaMap = t['tiendas'] is Map ? t['tiendas'] as Map : {};
          final tiendaNombre = tiendaMap['nombre']?.toString() ?? 'Tienda #${t['tienda_id']}';

          DateTime? fechaCreacion;
          if (t['creado_en'] != null) {
            fechaCreacion = DateTime.tryParse(t['creado_en'].toString())?.toLocal();
          }
          final fechaTexto = fechaCreacion != null
              ? DateFormat('dd/MM/yyyy hh:mm a').format(fechaCreacion)
              : 'Fecha desconocida';

          final List<String> jerarquias = [];
          if (t['alcance_categoria'] != null) jerarquias.add(t['alcance_categoria'].toString());
          if (t['alcance_clase'] != null) jerarquias.add(t['alcance_clase'].toString());
          if (t['alcance_sub_clase'] != null) jerarquias.add(t['alcance_sub_clase'].toString());
          final alcanceTexto = jerarquias.isEmpty ? 'Toda la Tienda' : jerarquias.join(' > ');

          Color estadoColor;
          String estadoLabel;
          IconData estadoIcon;

          switch (estado) {
            case 'pendiente_aprobacion':
              estadoColor = Colors.orangeAccent;
              estadoLabel = 'Pendiente de Aprobación';
              estadoIcon = Icons.pending_actions_rounded;
              break;
            case 'aplicada':
              estadoColor = Colors.greenAccent;
              estadoLabel = 'Aplicada / Finalizada';
              estadoIcon = Icons.check_circle_outline_rounded;
              break;
            case 'cancelada':
              estadoColor = Colors.redAccent;
              estadoLabel = 'Cancelada';
              estadoIcon = Icons.cancel_outlined;
              break;
            case 'conteo':
            case 'en_proceso':
            default:
              estadoColor = Colors.tealAccent;
              estadoLabel = 'En Conteo / Progreso';
              estadoIcon = Icons.edit_note_rounded;
              break;
          }

          return Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: estadoColor.withValues(alpha: 0.3), width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Cabecera de la tarjeta ───────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: estadoColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(estadoIcon, color: estadoColor, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              estadoLabel,
                              style: TextStyle(color: estadoColor, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        fechaTexto,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Datos de la Toma ─────────────────────────────────────
                  Text(
                    tiendaNombre,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.category_outlined, color: Colors.white38, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          alcanceTexto,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Botón de Acción según Estado ──────────────────────────
                  if (estado == 'conteo' || estado == 'en_proceso')
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.tealAccent.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('CONTINUAR CONTEO', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ConteoTomaPage(tomaId: tomaId),
                                ),
                              );
                              _cargarHistorial();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Botón eliminar (solo tomas sin productos contados)
                        Tooltip(
                          message: 'Eliminar toma vacía',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _eliminarToma(tomaId),
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: estado == 'pendiente_aprobacion'
                              ? Colors.orangeAccent.shade700
                              : const Color(0xFF2E3842),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(
                          estado == 'pendiente_aprobacion'
                              ? Icons.fact_check_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        label: Text(
                          estado == 'pendiente_aprobacion'
                              ? 'REVISAR Y AUDITAR DISCREPANCIAS'
                              : 'VER REPORTE DE LA TOMA',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RevisionTomaPage(tomaId: tomaId),
                            ),
                          );
                          _cargarHistorial();
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
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
