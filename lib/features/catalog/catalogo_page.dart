import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:catalogo_digital_app/app.dart';
import 'package:catalogo_digital_app/features/auth/sin_tienda_page.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';
import 'package:catalogo_digital_app/services/update_service.dart';
import 'package:catalogo_digital_app/features/catalog/checkout_form_widget.dart';
import 'package:catalogo_digital_app/features/catalog/product_list_widget.dart';

class CatalogoPage extends StatefulWidget {
  const CatalogoPage({super.key});

  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> with RouteAware {
  final GlobalKey<ProductListWidgetState> _productListKey = GlobalKey<ProductListWidgetState>();

  bool _isConfirming = false;
  bool _isCatalogExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inicializarCatalogo();
    });
    TiendaService().tiendaSeleccionadaId.addListener(_onTiendaChanged);
  }

  Future<void> _inicializarCatalogo() async {
    await TiendaService().cargarTiendas();
    if (mounted) {
      _productListKey.currentState?.refrescar();
      UpdateService.verificarActualizacion(context, silencioso: true);
    }
  }

  void _onTiendaChanged() {
    if (mounted) {
      _productListKey.currentState?.refrescar();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      routeObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void didPopNext() {
    _productListKey.currentState?.refrescar();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    TiendaService().tiendaSeleccionadaId.removeListener(_onTiendaChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (TiendaService().sinTiendaAsignada) {
      return const SinTiendaPage();
    }

    if (_isCatalogExpanded) {
      return ProductListWidget(
        key: _productListKey,
        onCerrarCatalogo: () {
          ScaffoldMessenger.of(context).clearSnackBars();
          setState(() {
            _isCatalogExpanded = false;
          });
        },
        onProductoAgregado: (producto, cantidad, stockActual) {
          CartService().agregarProducto(producto, cantidad, stockActual: stockActual);
          setState(() {});
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      drawer: const MenuLateral(),
      appBar: AppBar(
        title: const Text(
          "Módulo de Ventas",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: CheckoutFormWidget(
        isConfirming: _isConfirming,
        onConfirmingChanged: (val) {
          setState(() => _isConfirming = val);
        },
        onVerCatalogoPressed: () {
          setState(() {
            _isCatalogExpanded = true;
          });
        },
        onVentaExitosa: () {
          CartService().limpiar();
          _productListKey.currentState?.refrescar();
          if (mounted) setState(() {});
        },
        productosAgregadosWidget: _buildAddedProductsSection(),
      ),
    );
  }

  // ─── Added Products Section ──────────────────────────────────────────────────
  Widget _buildCircularButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _buildAddedProductsSection() {
    return ValueListenableBuilder<int>(
      valueListenable: CartService().itemsCountNotifier,
      builder: (context, count, child) {
        final items = CartService().items;
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                "Productos en el Pedido",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCircularButton(
                                  icon: Icons.remove,
                                  color: Colors.white70,
                                  onTap: () {
                                    CartService().actualizarCantidad(item.id, item.cantidad - 1);
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(width: 2),
                                GestureDetector(
                                  onTap: () async {
                                    final ctrl = TextEditingController(text: item.cantidad.toString());
                                    final int? result = await showDialog<int>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: const Color(0xFF1E1E1E),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        title: const Text(
                                          'Editar Cantidad',
                                          style: TextStyle(color: Colors.white, fontSize: 15),
                                        ),
                                        content: TextField(
                                          controller: ctrl,
                                          autofocus: true,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(
                                            border: UnderlineInputBorder(
                                              borderSide: BorderSide(color: Colors.blueAccent),
                                            ),
                                            focusedBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(color: Colors.blueAccent, width: 2),
                                            ),
                                          ),
                                          onTap: () => ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                                            onPressed: () {
                                              final n = int.tryParse(ctrl.text);
                                              Navigator.pop(ctx, n);
                                            },
                                            child: const Text('GUARDAR', style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                    ctrl.dispose();
                                    if (result != null && result > 0) {
                                      CartService().actualizarCantidad(item.id, result);
                                      setState(() {});
                                    } else if (result == 0) {
                                      CartService().eliminarProducto(item.id);
                                      setState(() {});
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      '${item.cantidad}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                _buildCircularButton(
                                  icon: Icons.add,
                                  color: Colors.blueAccent,
                                  onTap: () {
                                    CartService().actualizarCantidad(item.id, item.cantidad + 1);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      "P.U. S/.${item.precio.toStringAsFixed(2)}",
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      "P.T. S/.${(item.precio * item.cantidad).toStringAsFixed(2)}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E1E),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Eliminar Producto',
                                            style: TextStyle(color: Colors.white, fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                    content: Text(
                                      '¿Desea eliminar "${item.nombre}" de la orden?',
                                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text(
                                          'CANCELAR',
                                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text(
                                          'ELIMINAR',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  CartService().eliminarProducto(item.id);
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
