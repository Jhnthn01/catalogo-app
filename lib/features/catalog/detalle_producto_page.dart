import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/widgets/selector_tienda.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/widgets/menu_lateral.dart';
import 'package:catalogo_digital_app/features/inventory/kardex_screen.dart';

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
  late TextEditingController _aluController;
  late TextEditingController _descripcion2Controller;
  late TextEditingController _costoController;
  late TextEditingController _precioVentaController;

  DateTime? _fechaUltimoCosto;
  DateTime? _fechaUltimoCostoOriginal;

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
    _descripcion2Controller = TextEditingController(
      text: widget.producto['descripcion_2'],
    );
    _skuController = TextEditingController(text: widget.producto['sku']);
    _aluController = TextEditingController(text: widget.producto['alu']);
    _costoController = TextEditingController(
      text: widget.producto['costo']?.toString() ?? '0.0',
    );
    _precioVentaController = TextEditingController(
      text: widget.producto['precio_venta']?.toString() ?? '0.0',
    );

    DateTime? rawFecha;
    if (widget.producto['fecha_ultimo_costo'] != null) {
      rawFecha = DateTime.tryParse(widget.producto['fecha_ultimo_costo'].toString());
    } else if (widget.producto['ultimo_costo_at'] != null) {
      rawFecha = DateTime.tryParse(widget.producto['ultimo_costo_at'].toString());
    } else if (widget.producto['created_at'] != null && (double.tryParse(widget.producto['ultimo_costo']?.toString() ?? '') ?? 0) > 0) {
      rawFecha = DateTime.tryParse(widget.producto['created_at'].toString());
    }
    _fechaUltimoCosto = rawFecha?.toLocal();
    _fechaUltimoCostoOriginal = _fechaUltimoCosto;

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
          
      final tiendaId = TiendaService().tiendaActivaId.value;
      final rol = TiendaService().usuarioRol?.toLowerCase() ?? 'cliente';
      final bool esOperativo = !(rol == 'admin' || rol == 'administrador' || rol == 'gerente');

      if (tiendaId != null) {
        query = query.eq('tienda_id', tiendaId);
      } else if (esOperativo) {
        query = query.eq('tienda_id', -1);
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
        _esPantallaInventario ? 'Volver al inventario' : 'Volver a Ventas';
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
          IconButton(
            tooltip: 'Ver Kardex / Movimientos',
            icon: const Icon(Icons.history_toggle_off, color: Colors.tealAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => KardexScreen(
                    initialProductoId: widget.producto['id']?.toString(),
                    initialProductoNombre: widget.producto['descripcion_1']?.toString(),
                    initialSku: widget.producto['sku']?.toString(),
                  ),
                ),
              );
            },
          ),
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
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(
              "Nombre del Producto (Descripción 1)",
              _nameController,
              enabled: _modoEdicion && puedeGestionFicha,
            ),
            const SizedBox(height: 15),
            _buildTextField(
              "Descripción 2 / Especificaciones",
              _descripcion2Controller,
              enabled: _modoEdicion && puedeGestionFicha,
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _buildTextField("SKU", _skuController, enabled: false)),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    "ALU",
                    _aluController,
                    enabled: _modoEdicion && puedeGestionFicha,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (userRol == 'admin' || userRol == 'gerente') ...[
              const Text(
                "TIENDA A CONSULTAR",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const SizedBox(height: 6),
              const SelectorTienda(),
              const SizedBox(height: 15),
            ],
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
            if (mostrarCosto) ...[
              _buildTextField(
                "COSTO",
                _costoController,
                enabled: _modoEdicion && puedeGestionFicha,
                isNumeric: true,
                onChanged: (val) {
                  if (_fechaUltimoCosto == _fechaUltimoCostoOriginal) {
                    setState(() {
                      _fechaUltimoCosto = DateTime.now();
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildFechaUltimoCostoField(enabled: _modoEdicion && puedeGestionFicha),
              const SizedBox(height: 20),
            ],
            // ── Tarjetas informativas de costos (solo admin/gerente) ──────────
            if (puedeGestionFicha) ...[
              _buildCostInfoRow(
                ultimoCosto: widget.producto['ultimo_costo'],
                costoMedio: widget.producto['costo_medio'],
                fechaUltimoCosto: _fechaUltimoCosto,
              ),
              const SizedBox(height: 20),
            ],
            _buildTextField(
              "PRECIO VENTA PÚBLICO",
              _precioVentaController,
              enabled: _modoEdicion && puedeGestionFicha,
              onChanged: (v) => _calcularTotal(),
            ),
            const SizedBox(height: 15),
            if (esPersonal) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: const BorderSide(color: Colors.tealAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => KardexScreen(
                          initialProductoId: widget.producto['id']?.toString(),
                          initialProductoNombre: widget.producto['descripcion_1']?.toString(),
                          initialSku: widget.producto['sku']?.toString(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history_toggle_off, size: 20),
                  label: const Text(
                    'Ver Kardex de este Producto',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
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
                  text: "S/. ${_totalVenta.toStringAsFixed(2)}",
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
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final double? nuevoCosto = double.tryParse(_costoController.text);
      final double? costoAnterior = double.tryParse(widget.producto['costo']?.toString() ?? '');
      final bool costoModificado = nuevoCosto != null &&
          (costoAnterior == null || (nuevoCosto - costoAnterior).abs() > 0.0001);

      DateTime? fechaAGuardar = _fechaUltimoCosto;
      // Si el costo numérico cambió y el usuario no editó manualmente la fecha, se asigna ahora
      if (costoModificado && _fechaUltimoCosto == _fechaUltimoCostoOriginal) {
        fechaAGuardar = DateTime.now();
      } else if (fechaAGuardar == null && nuevoCosto != null && nuevoCosto > 0) {
        fechaAGuardar = DateTime.now();
      }

      final String? fechaUltimoCostoIso = fechaAGuardar?.toUtc().toIso8601String();

      final Map<String, dynamic> updateProducto = {
        'descripcion_1': _nameController.text.trim(),
        'descripcion_2': _descripcion2Controller.text.trim(),
        'alu': _aluController.text.trim(),
        'precio_venta': double.tryParse(_precioVentaController.text),
        'costo': nuevoCosto,
        'ultimo_costo': nuevoCosto,
        'modificado_por': currentUserId,
        'modificado_at': nowIso,
      };

      if (fechaUltimoCostoIso != null) {
        updateProducto['fecha_ultimo_costo'] = fechaUltimoCostoIso;
      }

      await Supabase.instance.client
          .from('productos')
          .update(updateProducto)
          .eq('id', widget.producto['id']);

      for (var s in _stocks) {
        final idStr = s['id'].toString();
        final controller = _stockControllers[idStr];
        if (controller != null) {
          final nuevoStock = int.tryParse(controller.text) ?? 0;
          await Supabase.instance.client.from('inventario').update({
            'stock': nuevoStock,
            'actualizado_at': nowIso,
            'usuario_id': currentUserId,
          }).eq('id', s['id']);
        }
      }

      // Sincronizar datos locales en el mapa
      widget.producto['descripcion_1'] = updateProducto['descripcion_1'];
      widget.producto['descripcion_2'] = updateProducto['descripcion_2'];
      widget.producto['alu'] = updateProducto['alu'];
      widget.producto['precio_venta'] = updateProducto['precio_venta'];
      widget.producto['costo'] = updateProducto['costo'];
      widget.producto['ultimo_costo'] = updateProducto['ultimo_costo'];
      if (fechaUltimoCostoIso != null) {
        widget.producto['fecha_ultimo_costo'] = fechaUltimoCostoIso;
      }

      if (mounted) {
        setState(() {
          _modoEdicion = false;
          _fechaUltimoCosto = fechaAGuardar;
          _fechaUltimoCostoOriginal = fechaAGuardar;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Producto actualizado con éxito"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error al guardar: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _seleccionarFechaUltimoCosto() async {
    final initial = _fechaUltimoCosto ?? DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
          ),
          child: child!,
        );
      },
    );

    final selectedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime?.hour ?? initial.hour,
      pickedTime?.minute ?? initial.minute,
    );

    setState(() {
      _fechaUltimoCosto = selectedDateTime;
    });
  }

  Widget _buildFechaUltimoCostoField({required bool enabled}) {
    final String fechaFmt = _fechaUltimoCosto != null
        ? DateFormat('dd/MM/yyyy HH:mm:ss').format(_fechaUltimoCosto!)
        : 'Sin registrar (se asignará automáticamente al guardar)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'FECHA DEL ÚLTIMO COSTO',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            if (enabled)
              const Text(
                'Toca para editar',
                style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: enabled ? _seleccionarFechaUltimoCosto : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: enabled ? Colors.grey.shade900 : Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: enabled ? Colors.blueAccent.withOpacity(0.5) : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  color: enabled ? Colors.blueAccent : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fechaFmt,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white54,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (enabled) ...[
                  IconButton(
                    tooltip: 'Usar fecha y hora actual',
                    icon: const Icon(Icons.today, color: Colors.tealAccent, size: 20),
                    onPressed: () {
                      setState(() => _fechaUltimoCosto = DateTime.now());
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Seleccionar en calendario',
                    icon: const Icon(Icons.edit_calendar, color: Colors.blueAccent, size: 20),
                    onPressed: _seleccionarFechaUltimoCosto,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
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

  /// Muestra las tarjetas de Último Costo y Costo Medio Variable (PMP).
  /// Solo visible para admin/gerente cuando puedeGestionFicha == true.
  Widget _buildCostInfoRow({dynamic ultimoCosto, dynamic costoMedio, DateTime? fechaUltimoCosto}) {
    final double? baseCosto = double.tryParse(widget.producto['costo']?.toString() ?? '');
    final double? rawUc = ultimoCosto != null ? double.tryParse(ultimoCosto.toString()) : null;
    final double? rawCm = costoMedio != null ? double.tryParse(costoMedio.toString()) : null;

    final double? uc = (rawUc != null && rawUc > 0) ? rawUc : baseCosto;
    final double? cm = (rawCm != null && rawCm > 0) ? rawCm : baseCosto;

    String formatMonto(double? v) =>
        v != null ? 'S/. ${v.toStringAsFixed(2)}' : '—';

    final String fechaTexto = fechaUltimoCosto != null
        ? DateFormat('dd/MM/yyyy HH:mm:ss').format(fechaUltimoCosto)
        : 'Sin registrar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COSTOS DE ABASTECIMIENTO',
          style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // ── Último Costo de Compra ───────────────────────────────
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade900,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long, color: Colors.blueAccent, size: 14),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Último Costo\nde Compra',
                            style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatMonto(uc),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 11, color: Colors.white38),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            fechaTexto,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // ── Costo Medio Variable (PMP) ───────────────────────────
            Expanded(
              child: Tooltip(
                message: 'El costo medio se recalculó automáticamente\nen la última recepción de abastecimiento.',
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(color: Colors.white70, fontSize: 11),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_graph, color: Colors.tealAccent, size: 14),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Costo Medio\nVariable (PMP)',
                              style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Icon(Icons.info_outline, color: Colors.white24, size: 14),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatMonto(cm),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Ponderado auto',
                        style: TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}