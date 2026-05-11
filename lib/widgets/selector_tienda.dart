import 'package:flutter/material.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';

class SelectorTienda extends StatefulWidget {
  const SelectorTienda({super.key});

  @override
  State<SelectorTienda> createState() => _SelectorTiendaState();
}

class _SelectorTiendaState extends State<SelectorTienda> {
  final TiendaService _tiendaService = TiendaService();

  @override
  void initState() {
    super.initState();
    _cargarTiendasSiEsNecesario();
  }

  Future<void> _cargarTiendasSiEsNecesario() async {
    if (_tiendaService.tiendas.isEmpty) {
      await _tiendaService.cargarTiendas();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tiendaService.tiendas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: Center(
          child: SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      );
    }

    return ValueListenableBuilder<int?>(
      valueListenable: _tiendaService.tiendaSeleccionadaId,
      builder: (context, tiendaId, child) {
        return Container(
          width: double.infinity,
          height: 48, // To match roughly the TextField height
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: tiendaId,
              dropdownColor: const Color(0xFF2C2C2C),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  _tiendaService.seleccionarTienda(newValue);
                }
              },
              items: _tiendaService.tiendas.map((Map<String, dynamic> tienda) {
                return DropdownMenuItem<int>(
                  value: tienda['id'] as int,
                  child: Text(tienda['nombre'] as String),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
