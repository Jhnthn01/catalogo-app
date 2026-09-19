import 'package:flutter/material.dart';

/// Componente reutilizable para la búsqueda multi-token (%):
/// Incluye campo de texto, selector de modo ("Todas" / "Cualquiera")
/// y chips interactivos de prioridad.
class BuscadorProductosWidget extends StatefulWidget {
  final TextEditingController controller;
  final String modoBusqueda; // 'todas' | 'cualquiera'
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onModoChanged;
  final VoidCallback? onScanPressed;
  final String hintText;
  final bool mostrarModoSelector;
  final bool mostrarChips;
  final bool mostrarEscaner;

  const BuscadorProductosWidget({
    super.key,
    required this.controller,
    required this.modoBusqueda,
    required this.onQueryChanged,
    required this.onModoChanged,
    this.onScanPressed,
    this.hintText = 'Buscar por SKU, Nombre, Marca, UPC o ALU...',
    this.mostrarModoSelector = true,
    this.mostrarChips = true,
    this.mostrarEscaner = true,
  });

  @override
  State<BuscadorProductosWidget> createState() => _BuscadorProductosWidgetState();
}

class _BuscadorProductosWidgetState extends State<BuscadorProductosWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(),
        if (widget.mostrarModoSelector) _buildModoSelector(),
        if (widget.mostrarChips) _buildChipsBusqueda(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white12),
        ),
        child: TextField(
          controller: widget.controller,
          onChanged: widget.onQueryChanged,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                    onPressed: () {
                      widget.controller.clear();
                      widget.onQueryChanged('');
                      setState(() {});
                    },
                  ),
                if (widget.mostrarEscaner && widget.onScanPressed != null)
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent, size: 20),
                    onPressed: widget.onScanPressed,
                  ),
              ],
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildModoSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Text(
            'Modo de búsqueda:',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'todas',
                  label: Text('Todas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  icon: Icon(Icons.all_inclusive, size: 14),
                ),
                ButtonSegment<String>(
                  value: 'cualquiera',
                  label: Text('Cualquiera', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  icon: Icon(Icons.alt_route, size: 14),
                ),
              ],
              selected: {widget.modoBusqueda},
              onSelectionChanged: (Set<String> newSelection) {
                final newModo = newSelection.first;
                if (newModo != widget.modoBusqueda) {
                  widget.onModoChanged(newModo);
                }
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                side: WidgetStateProperty.all(
                  const BorderSide(color: Colors.blueAccent, width: 1.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipsBusqueda() {
    final q = widget.controller.text.trim();
    final List<String> tokens = q.contains('%')
        ? q.split('%').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        : (q.isNotEmpty ? [q] : []);

    if (tokens.isEmpty) return const SizedBox.shrink();

    final bool esModoCualquiera = widget.modoBusqueda == 'cualquiera';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                esModoCualquiera
                    ? 'Prioridad de búsqueda:'
                    : 'Tokens de búsqueda (Todos obligatorios):',
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              if (esModoCualquiera && tokens.length > 1) ...[
                const SizedBox(width: 6),
                const Text(
                  '(Toca una etiqueta para moverla al 1er lugar)',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(tokens.length, (index) {
              final token = tokens[index];
              final bool esPrincipal = esModoCualquiera && index == 0 && tokens.length > 1;

              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: esModoCualquiera
                    ? () {
                        if (index == 0) return;
                        final newTokens = [token, ...tokens.where((t) => t != token)];
                        final newQuery = newTokens.join('%');
                        widget.controller.text = newQuery;
                        widget.onQueryChanged(newQuery);
                        setState(() {});
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: esPrincipal
                        ? Colors.amber.withValues(alpha: 0.2)
                        : Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: esPrincipal ? Colors.amberAccent : Colors.blueAccent.withValues(alpha: 0.4),
                      width: esPrincipal ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        esPrincipal ? Icons.star_rounded : Icons.search_rounded,
                        color: esPrincipal ? Colors.amberAccent : Colors.blueAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        token,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: esPrincipal ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      if (esPrincipal) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Prioridad 1',
                            style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          final newTokens = List<String>.from(tokens)..remove(token);
                          final newQuery = newTokens.join('%');
                          widget.controller.text = newQuery;
                          widget.onQueryChanged(newQuery);
                          setState(() {});
                        },
                        child: const Icon(Icons.close, color: Colors.white70, size: 14),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
