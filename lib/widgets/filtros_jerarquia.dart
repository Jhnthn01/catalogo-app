import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FiltrosJerarquiaWidget extends StatefulWidget {
  final Function(String? categoria, String? clase, String? subClase) onFiltrosCambiados;

  const FiltrosJerarquiaWidget({super.key, required this.onFiltrosCambiados});

  @override
  State<FiltrosJerarquiaWidget> createState() => _FiltrosJerarquiaWidgetState();
}

class _FiltrosJerarquiaWidgetState extends State<FiltrosJerarquiaWidget> {
  bool _isLoading = true;
  
  // Memoria completa de combinaciones
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
      final data = await Supabase.instance.client.rpc('get_categorias_jerarquia');
      if (mounted) {
        setState(() {
          _jerarquiaCompleta = List<Map<String, dynamic>>.from(data);
          
          // Llenamos el primer dropdown extrayendo las categorias unicas
          _categorias = _jerarquiaCompleta
              .map((e) => e['categoria']?.toString() ?? '')
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList();
          _categorias.sort();
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fallo al cargar jerarquias: $e");
      if (mounted) setState(() => _isLoading = false);
    }
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
            .where((item) => item['categoria'] == nuevaCategoria)
            .map((e) => e['clase']?.toString() ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList();
        _clases.sort();
      }
    });
    
    widget.onFiltrosCambiados(_catSeleccionada, _claseSeleccionada, _subClaseSeleccionada);
  }

  void _onClaseCambiada(String? nuevaClase) {
    if (nuevaClase == _claseSeleccionada) return;
    
    setState(() {
      _claseSeleccionada = nuevaClase;
      _subClaseSeleccionada = null;
      
      if (nuevaClase == null) {
        _subClases = [];
      } else {
        _subClases = _jerarquiaCompleta
            .where((item) => item['categoria'] == _catSeleccionada && item['clase'] == nuevaClase)
            .map((e) => e['sub_clase']?.toString() ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList();
        _subClases.sort();
      }
    });

    widget.onFiltrosCambiados(_catSeleccionada, _claseSeleccionada, _subClaseSeleccionada);
  }

  void _onSubClaseCambiada(String? nuevaSubClase) {
    setState(() => _subClaseSeleccionada = nuevaSubClase);
    widget.onFiltrosCambiados(_catSeleccionada, _claseSeleccionada, _subClaseSeleccionada);
  }

  void _limpiarFiltros() {
    setState(() {
      _catSeleccionada = null;
      _claseSeleccionada = null;
      _subClaseSeleccionada = null;
      _clases = [];
      _subClases = [];
    });
    widget.onFiltrosCambiados(null, null, null);
  }

  Widget _buildDropdown(String label, List<String> opciones, String? valorActual, Function(String?) onChanged) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF2C2C2C),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blueAccent, size: 20),
          hint: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          value: valorActual,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          onChanged: onChanged,
          items: opciones.map((String valor) {
             return DropdownMenuItem<String>(
               value: valor,
               child: Text(valor, overflow: TextOverflow.ellipsis),
             );
          }).toList(),
        ),
      ),
    );
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

    // Permite que la barra sea scrolleable horizontalmente para que quepan todos los inputs fluidamente
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.filter_list, color: Colors.white54),
            const SizedBox(width: 8),
            _buildDropdown("Categoría", _categorias, _catSeleccionada, _onCategoriaCambiada),
            const SizedBox(width: 8),
            
            if (_clases.isNotEmpty) ...[
              _buildDropdown("Clase", _clases, _claseSeleccionada, _onClaseCambiada),
              const SizedBox(width: 8),
            ],

            if (_subClases.isNotEmpty) ...[
              _buildDropdown("Sub Clase", _subClases, _subClaseSeleccionada, _onSubClaseCambiada),
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
