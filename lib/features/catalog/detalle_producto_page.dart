import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/widgets/selector_tienda.dart';
import 'package:catalogo_digital_app/features/cart/carrito_page.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';

enum DetalleProductoOrigen { catalogo, inventario }

class DetalleProductoPage extends StatefulWidget {
  final Map<String, dynamic> producto;
  final DetalleProductoOrigen origen;

  final bool contextoInventario;

  const DetalleProductoPage({
    super.key,
    required this.producto,
    this.origen = DetalleProductoOrigen.catalogo,
    this.contextoInventario = false,
  });

  @override
  State<DetalleProductoPage> createState() => _DetalleProductoPageState();
}

class _DetalleProductoPageState extends State<DetalleProductoPage> {
  late TextEditingController _nameController;
  late TextEditingController _skuController;
  late TextEditingController _costoController;
  late TextEditingController _precioVentaController;

  int _cantidadAReservar = 0;
  double _totalVenta = 0.0;
  List<dynamic> _stocks = [];
  final Map<String, TextEditingController> _stockControllers = {};
  String userRol = 'cliente';
  bool _modoEdicion = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.producto['descripcion_1'],
    );
    _skuController = TextEditingController(text: widget.producto['sku']);
    _costoController = TextEditingController(
      text: widget.producto['costo']?.toString() ?? '0.0',
    );
    _precioVentaController = TextEditingController(
      text: widget.producto['precio_venta']?.toString() ?? '0.0',
    );

    _checkUserRole();
    _fetchStock();
    _calcularTotal();
    TiendaService().tiendaSeleccionadaId.addListener(_onTiendaChanged);
  }

  void _onTiendaChanged() {
    if (mounted) {
      _fetchStock();
    }
  }


  // CORRECCIÓN 1: Eliminado try duplicado y llaves balanceadas
  Future<void> _fetchStock() async {
    try {
      var query = Supabase.instance.client
          .from('inventario')
          .select('id, stock, tiendas(codigo_tienda, nombre)')
          .eq('producto_id', widget.producto['id']);
          
      final tiendaId = TiendaService().tiendaSeleccionadaId.value;
      if (tiendaId != null) {
        query = query.eq('tienda_id', tiendaId);
      }

      final data = await query;
      if (mounted) {
        setState(() {
          _stocks = data;
          _stockControllers.clear();
          for (var s in data) {
            _stockControllers[s['id'].toString()] =
                TextEditingController(text: s['stock'].toString());
          }
        });
      }
    } catch (e) {
      debugPrint("Error cargando stock: $e");
    }
  }

  Future<void> _checkUserRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('perfiles')
          .select('rol')
          .eq('id', user.id)
          .maybeSingle();
      final rol = data?['rol'] as String? ?? 'cliente';
      if (!mounted) return;
      setState(() {
        userRol = rol;
        if (_esPantallaInventario && _rolPuedeGestionarInventario(rol)) {
          _modoEdicion = true;
        }
      });
    } catch (e) {
      debugPrint('Error cargando rol: $e');
    }
  }

  bool _rolPuedeGestionarInventario(String rol) {
    return rol == 'admin' || rol == 'gerente';
  }

  bool get _esPantallaInventario =>
      widget.contextoInventario ||
      widget.origen == DetalleProductoOrigen.inventario;

  void _calcularTotal() {
    double precio = double.tryParse(_precioVentaController.text) ?? 0.0;
    setState(() => _totalVenta = precio * _cantidadAReservar);
  }

  int get _stockTotal {
    int sum = 0;
    for (var s in _stocks) {
      sum += (s['stock'] as num).toInt();
    }
    return sum;
  }

  @override
  void dispose() {
    TiendaService().tiendaSeleccionadaId.removeListener(_onTiendaChanged);
    _nameController.dispose();
    _skuController.dispose();
    _costoController.dispose();
    _precioVentaController.dispose();
    for (var controller in _stockControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool esPersonal =
        (userRol == 'admin' || userRol == 'gerente' || userRol == 'almacenista' || userRol == 'cajero' || userRol == 'vendedor');
    final bool puedeGestionFicha = _rolPuedeGestionarInventario(userRol);
    final bool esModoInventario = _esPantallaInventario;
    final bool mostrarBloquePedidos = !_esPantallaInventario;
    final bool mostrarSwitchEdicion =
        esModoInventario ? puedeGestionFicha : esPersonal;
    final bool mostrarCosto =
        esModoInventario ? puedeGestionFicha : esPersonal;
    final String tooltipAtras =
        _esPantallaInventario ? 'Volver al inventario' : 'Volver al catálogo';
    final String tituloAppBar =
        esModoInventario ? 'Gestión de producto' : 'Detalle';

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      drawer: const MenuLateral(),
      appBar: AppBar(
        leading: IconButton(
          tooltip: tooltipAtras,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tituloAppBar, style: const TextStyle(fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (mostrarSwitchEdicion)
            Row(
              children: [
                Text(
                  esModoInventario
                      ? (_modoEdicion ? 'Modo edición' : 'Modo lectura')
                      : 'Editar',
                  style: const TextStyle(fontSize: 12),
                ),
                Switch(
                  value: _modoEdicion,
                  activeThumbColor: Colors.blue,
                  onChanged: (val) => setState(() => _modoEdicion = val),
                ),
              ],
            ),
          if (mostrarBloquePedidos)
            ValueListenableBuilder<int>(
              valueListenable: CartService().itemsCountNotifier,
              builder: (context, count, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.shopping_cart_outlined,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CarritoPage(),
                        ),
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (mostrarBloquePedidos) const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(
              "Nombre del Producto",
              _nameController,
              enabled: _modoEdicion && puedeGestionFicha,
            ),
            const SizedBox(height: 20),
            _buildTextField("SKU", _skuController, enabled: false),
            const SizedBox(height: 20),
            const Text(
              "TIENDA A CONSULTAR",
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(height: 6),
            const SelectorTienda(),
            const SizedBox(height: 15),
            const Text(
              "STOCK POR TIENDA",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_stocks.isEmpty)
              const Text(
                "Consultando stock...",
                style: TextStyle(color: Colors.white54),
              )
            else
              ..._stocks.map((s) {
                final idStr = s['id'].toString();
                final controller = _stockControllers[idStr];
                if (controller == null) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          "Tienda: ${s['tiendas']['nombre']}",
                          controller,
                          enabled: _modoEdicion && userRol == 'admin',
                          isNumeric: true,
                        ),
                      ),
                      if (_modoEdicion && userRol != 'admin') ...[
                        const SizedBox(width: 10),
                        Container(
                          margin: const EdgeInsets.only(top: 18),
                          child: IconButton(
                            icon: const Icon(Icons.report_problem_outlined, color: Colors.orangeAccent),
                            tooltip: "Reportar conteo físico",
                            onPressed: () => _mostrarDialogoAjuste(idStr, s['tiendas']['nombre'], s['stock']),
                          ),
                        )
                      ]
                    ],
                  ),
                );
              }),
            const SizedBox(height: 20),
            if (mostrarCosto)
              _buildTextField("COSTO", _costoController, enabled: _modoEdicion && puedeGestionFicha),
            const SizedBox(height: 20),
            _buildTextField(
              "PRECIO VENTA PÚBLICO",
              _precioVentaController,
              enabled: _modoEdicion && puedeGestionFicha,
              onChanged: (v) => _calcularTotal(),
            ),
            if (mostrarBloquePedidos) ...[
              const Divider(height: 40, color: Colors.white10),
              const Text(
                "COMPRAS / PEDIDOS",
                style:
                    TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              const Text(
                "CANTIDAD A ANADIR",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => _mostrarDialogoCantidad(onSuccess: null),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.blue.withOpacity(0.5))),
                        child: Text(
                          "$_cantidadAReservar",
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            if (_cantidadAReservar > 0) {
                              setState(() => _cantidadAReservar--);
                              _calcularTotal();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.greenAccent,
                          ),
                          onPressed: () {
                            setState(() => _cantidadAReservar++);
                            _calcularTotal();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                "SUBTOTAL",
                TextEditingController(
                  text: "\$ ${_totalVenta.toStringAsFixed(2)}",
                ),
                enabled: false,
              ),
            ],
            if (_stockTotal <= 0 && !esModoInventario && _stocks.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent, width: 1.5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "⚠️ Stock del sistema en 0. Se procederá con venta en físico y el pedido será marcado para regularización.",
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: _botonAccionPrincipal(
                esModoInventario: esModoInventario,
                puedeGestionFicha: puedeGestionFicha,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botonAccionPrincipal({
    required bool esModoInventario,
    required bool puedeGestionFicha,
  }) {
    if (esModoInventario) {
      if (!puedeGestionFicha) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No tienes permisos para editar este producto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        );
      }
      if (!_modoEdicion) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Activa la edición con el interruptor superior para modificar la ficha.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        );
      }
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          padding: const EdgeInsets.all(15),
        ),
        onPressed: _guardarCambios,
        child: const Text('GUARDAR CAMBIOS'),
      );
    }

    if (_modoEdicion && userRol == 'admin') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          padding: const EdgeInsets.all(15),
        ),
        onPressed: _guardarCambios,
        child: const Text('GUARDAR CAMBIOS'),
      );
    }

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            _cantidadAReservar > 0 ? Colors.green : Colors.grey,
        padding: const EdgeInsets.all(15),
      ),
      onPressed: () {
        if (_cantidadAReservar > 0) {
          _agregarAlPedido();
        } else {
          _mostrarDialogoCantidad(onSuccess: _agregarAlPedido);
        }
      },
      icon: const Icon(Icons.add_shopping_cart),
      label: const Text('ANADIR AL PEDIDO'),
    );
  }

  void _agregarAlPedido() {
    if (_cantidadAReservar <= 0) return;
    final bool esSobreventa = _cantidadAReservar > _stockTotal;
    CartService().agregarProducto(
      widget.producto,
      _cantidadAReservar,
      stockActual: _stockTotal,
    );
    if (esSobreventa) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ ${_cantidadAReservar}x ${widget.producto['descripcion_1']} añadido — STOCK EN 0, venta en físico.',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.deepOrange.shade700,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'VER CARRITO',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CarritoPage(),
                ),
              );
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '¡${_cantidadAReservar}x ${widget.producto['descripcion_1']} añadido!',
          ),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'VER CARRITO',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CarritoPage(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _mostrarDialogoCantidad({Function()? onSuccess}) async {
    final TextEditingController qtyController =
        TextEditingController(text: _cantidadAReservar == 0 ? '' : _cantidadAReservar.toString());
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: const Text("Cantidad a añadir", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              hintText: "Ej. 10",
              hintStyle: TextStyle(color: Colors.white24)
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                final int? newQty = int.tryParse(qtyController.text);
                if (newQty != null && newQty > 0) {
                  setState(() => _cantidadAReservar = newQty);
                  _calcularTotal();
                  Navigator.pop(context);
                  if (onSuccess != null) {
                    onSuccess();
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text("GUARDAR", style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _mostrarDialogoAjuste(String inventarioId, String nombreTienda, dynamic stockActual) async {
    final TextEditingController qtyController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text("Reportar Conteo - $nombreTienda", style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Ingresa la cantidad física contada en piso:", style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 15),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.black26,
                  hintText: "Ej. 15",
                  hintStyle: TextStyle(color: Colors.white24)
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyController.text);
                if (qty == null || qty < 0) return;
                
                try {
                  final existe = await Supabase.instance.client
                    .from('ajustes_inventario')
                    .select('id')
                    .eq('inventario_id', inventarioId)
                    .eq('estado', 'pendiente')
                    .maybeSingle();

                  if (existe != null) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Ya hay una validación en progreso para este producto."),
                        backgroundColor: Colors.orange,
                      ));
                    }
                    return;
                  }

                  final user = Supabase.instance.client.auth.currentUser;
                  await Supabase.instance.client.from('ajustes_inventario').insert({
                    'inventario_id': inventarioId,
                    'usuario_id': user?.id,
                    'cantidad_reportada': qty,
                    'estado': 'pendiente'
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Solicitud enviada al gerente para su revisión."),
                      backgroundColor: Colors.green,
                    ));
                  }
                } catch (e) {
                  debugPrint("Error guardando ajuste: $e");
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              child: const Text("ENVIAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ]
        );
      }
    );
  }

  Future<void> _guardarCambios() async {
    bool stockModificado = false;
    
    if (userRol == 'admin') {
      for (var s in _stocks) {
        final idStr = s['id'].toString();
        final controller = _stockControllers[idStr];
        if (controller != null && controller.text != s['stock'].toString()) {
          stockModificado = true;
          break;
        }
      }
    }

    if (stockModificado) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Aviso de Cambio de Stock", style: TextStyle(color: Colors.orangeAccent)),
            content: const Text(
              "Estás editando el inventario físico directamente como Administrador. Este cambio se reflejará inmediatamente y de manera definitiva.\n\n¿Deseas continuar?",
              style: TextStyle(color: Colors.white70)
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("SÍ, CONTINUAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      ) ?? false;
      
      if (!confirmar) return;
    }

    try {
      await Supabase.instance.client.from('productos').update({
        'descripcion_1': _nameController.text,
        'precio_venta': double.tryParse(_precioVentaController.text),
        'costo': double.tryParse(_costoController.text),
      }).eq('id', widget.producto['id']);

      for (var s in _stocks) {
        final idStr = s['id'].toString();
        final controller = _stockControllers[idStr];
        if (controller != null) {
          final nuevoStock = int.tryParse(controller.text) ?? 0;
          await Supabase.instance.client.from('inventario').update({
            'stock': nuevoStock,
            'actualizado_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', s['id']);
        }
      }

      if (mounted) {
        setState(() => _modoEdicion = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Actualizado con éxito")));
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    bool isNumeric = false,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: enabled ? Colors.white : Colors.white54),
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled ? Colors.grey.shade900 : Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}