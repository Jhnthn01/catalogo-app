import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef FiltrosJerarquiaCallback = void Function(
  String? categoria,
  String? clase,
  String? subClase,
  int? subClaseId,
  List<int>? subClaseIds,
);

class FiltrosJerarquiaWidget extends StatefulWidget {
  final FiltrosJerarquiaCallback onFiltrosCambiados;

  const FiltrosJerarquiaWidget({super.key, required this.onFiltrosCambiados});

  @override
  State<FiltrosJerarquiaWidget> createState() => _FiltrosJerarquiaWidgetState();
}

class _FiltrosJerarquiaWidgetState extends State<FiltrosJerarquiaWidget> {
  bool _isLoading = true;
  
  // Memoria completa de combinaciones relacionales
  List<Map<String, dynamic>> _jerarquiaCompleta = [];

  // Opciones disponibles para pintar en pantalla 
  List<String> _categorias = [];
  List<String> _clases = [];
  List<String> _subClases = [];

  // Lo que seleccionó el usuario
  String? _catSeleccionada;
  String? _claseSeleccionada;
  String? _subClaseSeleccionada;

  @override
  void initState() {
    super.initState();
    _cargarDiccionario();
  }

  Future<void> _cargarDiccionario() async {
    try {
      List<Map<String, dynamic>> jerarquia = [];
      try {
        final res = await Supabase.instance.client
            .from('sub_clases')
            .select('id, nombre, clases!inner(id, nombre, categoria_id, categorias!inner(id, nombre))');

        if (res.isNotEmpty) {
          final List<Map<String, dynamic>> desdeTablas = [];
          for (final item in res) {
            final subNombre = item['nombre']?.toString().trim();
            final subId = item['id'] != null ? int.tryParse(item['id'].toString()) : null;
            final claseMap = item['clases'] as Map<String, dynamic>?;
            final claseNombre = claseMap?['nombre']?.toString().trim();
            final catMap = claseMap?['categorias'] as Map<String, dynamic>?;
            final catNombre = catMap?['nombre']?.toString().trim();

            if (catNombre != null && catNombre.isNotEmpty) {
              desdeTablas.add({
                'categoria': catNombre,
                'clase': claseNombre ?? '',
                'sub_clase': subNombre ?? '',
                'sub_clase_id': subId,
              });
            }
          }
          if (desdeTablas.isNotEmpty) {
            jerarquia = desdeTablas;
          }
        }
      } catch (eTablas) {
        debugPrint('Consulta directa a tablas normalizadas omitida: $eTablas');
      }

      // Si las tablas directas fallaron o están vacías, intentar RPC get_categorias_jerarquia
      if (jerarquia.isEmpty) {
        try {
          final data = await Supabase.instance.client.rpc('get_categorias_jerarquia');
          if (data != null && data is List) {
            jerarquia = List<Map<String, dynamic>>.from(data);
          }
        } catch (e) {
          debugPrint("Fallo al cargar jerarquias por RPC: $e");
        }
      }

      if (mounted) {
        setState(() {
          _jerarquiaCompleta = jerarquia;
          
          // Llenamos el primer dropdown extrayendo las categorias únicas
          _categorias = _jerarquiaCompleta
              .map((e) => e['categoria']?.toString().trim() ?? '')
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()..sort();
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fallo general al cargar jerarquias: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _esOpcionSinValor(String? valor) {
    if (valor == null) return true;
    final v = valor.trim().toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');
    if (v.isEmpty) return true;
    return v == 'sin categoria' ||
        v == 'sin categoría' ||
        v == 'sin clase' ||
        v == 'sin subclase' ||
        v == 'sin sub clase' ||
        v == 's/c' ||
        v == 's/s' ||
        v == 'n/a' ||
        v == 'na' ||
        v == 'ninguna' ||
        v == 'ninguno';
  }

  bool _soloOpcionesSinValor(List<String> opciones) {
    if (opciones.isEmpty) return true;
    return opciones.every(_esOpcionSinValor);
  }

  List<int>? _calcularSubClaseIds() {
    if (_catSeleccionada == null && _claseSeleccionada == null && _subClaseSeleccionada == null) {
      return null;
    }
    final ids = _jerarquiaCompleta
        .where((item) {
          if (_catSeleccionada != null && item['categoria']?.toString().trim() != _catSeleccionada) return false;
          if (_claseSeleccionada != null && item['clase']?.toString().trim() != _claseSeleccionada) return false;
          if (_subClaseSeleccionada != null && item['sub_clase']?.toString().trim() != _subClaseSeleccionada) return false;
          return true;
        })
        .map((e) => int.tryParse(e['sub_clase_id']?.toString() ?? ''))
        .whereType<int>()
        .toSet()
        .toList();
    return ids.isNotEmpty ? ids : null;
  }

  void _onCategoriaCambiada(String? nuevaCategoria) {
    if (nuevaCategoria == _catSeleccionada) return;
    
    setState(() {
      _catSeleccionada = nuevaCategoria;
      _claseSeleccionada = null;
      _subClaseSeleccionada = null;
      _subClases = [];
      
      if (nuevaCategoria == null) {
        _clases = [];
      } else {
        _clases = _jerarquiaCompleta
            .where((item) => (item['categoria']?.toString().trim() ?? '') == nuevaCategoria)
            .map((e) => e['clase']?.toString().trim() ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()..sort();

        // Si solo quedan opciones de "Sin Clase", cargamos también las subclases de la categoría
        // para determinar si subclase también queda únicamente con opciones "Sin Subclase".
        if (_soloOpcionesSinValor(_clases)) {
          _subClases = _jerarquiaCompleta
              .where((item) => (item['categoria']?.toString().trim() ?? '') == nuevaCategoria)
              .map((e) => e['sub_clase']?.toString().trim() ?? '')
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()..sort();
        }
      }
    });
    
    final subIds = _calcularSubClaseIds();
    widget.onFiltrosCambiados(_catSeleccionada, null, null, null, subIds);
  }

  void _onClaseCambiada(String? nuevaClase) {
    if (nuevaClase == _claseSeleccionada) return;
    if (_esOpcionSinValor(nuevaClase)) return;
    
    setState(() {
      _claseSeleccionada = nuevaClase;
      _subClaseSeleccionada = null;
      
      if (nuevaClase == null) {
        _subClases = [];
      } else {
        _subClases = _jerarquiaCompleta
            .where((item) =>
                (item['categoria']?.toString().trim() ?? '') == _catSeleccionada &&
                (item['clase']?.toString().trim() ?? '') == nuevaClase)
            .map((e) => e['sub_clase']?.toString().trim() ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()..sort();
      }
    });

    final subIds = _calcularSubClaseIds();
    widget.onFiltrosCambiados(_catSeleccionada, _claseSeleccionada, null, null, subIds);
  }

  void _onSubClaseCambiada(String? nuevaSubClase) {
    if (nuevaSubClase == _subClaseSeleccionada) return;
    if (_esOpcionSinValor(nuevaSubClase)) return;

    setState(() => _subClaseSeleccionada = nuevaSubClase);

    int? subId;
    if (nuevaSubClase != null) {
      final match = _jerarquiaCompleta.firstWhere(
        (item) =>
            (item['categoria']?.toString().trim() ?? '') == _catSeleccionada &&
            (item['clase']?.toString().trim() ?? '') == _claseSeleccionada &&
            (item['sub_clase']?.toString().trim() ?? '') == nuevaSubClase,
        orElse: () => {},
      );
      if (match.isNotEmpty && match['sub_clase_id'] != null) {
        subId = int.tryParse(match['sub_clase_id'].toString());
      }
    }

    final subIds = subId != null ? [subId] : _calcularSubClaseIds();
    widget.onFiltrosCambiados(_catSeleccionada, _claseSeleccionada, _subClaseSeleccionada, subId, subIds);
  }

  void _limpiarFiltros() {
    setState(() {
      _catSeleccionada = null;
      _claseSeleccionada = null;
      _subClaseSeleccionada = null;
      _clases = [];
      _subClases = [];
    });
    widget.onFiltrosCambiados(null, null, null, null, null);
  }

  Widget _buildDropdown({
    required String label,
    required List<String> opciones,
    required String? valorActual,
    required ValueChanged<String?>? onChanged,
    bool enabled = true,
    String? disabledTexto,
  }) {
    final bool isActuallyEnabled = enabled && onChanged != null;
    final String displayText = !isActuallyEnabled && disabledTexto != null
        ? disabledTexto
        : (valorActual ?? label);

    final widgetDropdown = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isActuallyEnabled ? const Color(0xFF1E1E1E) : const Color(0xFF161616),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActuallyEnabled ? Colors.white24 : Colors.white12,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF2C2C2C),
          icon: Icon(
            isActuallyEnabled ? Icons.keyboard_arrow_down : Icons.lock_outline,
            color: isActuallyEnabled ? Colors.blueAccent : Colors.white24,
            size: isActuallyEnabled ? 20 : 16,
          ),
          hint: Text(
            displayText,
            style: TextStyle(
              color: isActuallyEnabled ? Colors.white54 : Colors.white38,
              fontSize: 13,
              fontStyle: isActuallyEnabled ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          disabledHint: Text(
            displayText,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
          value: isActuallyEnabled ? valorActual : null,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          onChanged: isActuallyEnabled ? onChanged : null,
          items: isActuallyEnabled
              ? opciones.map((String valor) {
                  final bool esSin = _esOpcionSinValor(valor);
                  return DropdownMenuItem<String>(
                    value: valor,
                    enabled: !esSin,
                    child: Text(
                      valor,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: esSin ? Colors.white24 : Colors.white,
                        fontStyle: esSin ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  );
                }).toList()
              : null,
        ),
      ),
    );

    if (!isActuallyEnabled) {
      return Tooltip(
        message: "$label desactivado ($displayText)",
        child: widgetDropdown,
      );
    }
    return widgetDropdown;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_categorias.isEmpty) return const SizedBox.shrink(); // No hay estructura para filtrar aun

    final bool catDesactivada = _soloOpcionesSinValor(_categorias);

    final bool mostrarClase = _catSeleccionada != null;
    final bool claseDesactivada = _soloOpcionesSinValor(_clases);

    final bool mostrarSubClase = _claseSeleccionada != null ||
        (claseDesactivada && _catSeleccionada != null && _subClases.isNotEmpty);
    final bool subClaseDesactivada = _soloOpcionesSinValor(_subClases);

    // Permite que la barra sea scrolleable horizontalmente para que quepan todos los inputs fluidamente
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.filter_list, color: Colors.white54),
            const SizedBox(width: 8),
            _buildDropdown(
              label: "Categoría",
              opciones: _categorias,
              valorActual: _catSeleccionada,
              onChanged: catDesactivada ? null : _onCategoriaCambiada,
              enabled: !catDesactivada,
              disabledTexto: "Sin categoría",
            ),
            const SizedBox(width: 8),
            
            if (mostrarClase) ...[
              _buildDropdown(
                label: "Clase",
                opciones: _clases,
                valorActual: _claseSeleccionada,
                onChanged: claseDesactivada ? null : _onClaseCambiada,
                enabled: !claseDesactivada,
                disabledTexto: "Sin clase",
              ),
              const SizedBox(width: 8),
            ],

            if (mostrarSubClase) ...[
              _buildDropdown(
                label: "Sub Clase",
                opciones: _subClases,
                valorActual: _subClaseSeleccionada,
                onChanged: subClaseDesactivada ? null : _onSubClaseCambiada,
                enabled: !subClaseDesactivada,
                disabledTexto: "Sin sub_clase",
              ),
              const SizedBox(width: 8),
            ],

            if (_catSeleccionada != null)
               IconButton(
                 icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                 tooltip: "Limpiar filtros",
                 onPressed: _limpiarFiltros,
                 padding: EdgeInsets.zero,
                 constraints: const BoxConstraints(),
               )
          ],
        ),
      ),
    );
  }
}
