import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo interno para un ítem del carrito
// ─────────────────────────────────────────────────────────────────────────────
class _ItemCarrito {
  final String productoId;
  final String sku;
  final String descripcion;
  double cantidad;
  double costoUnitario;

  _ItemCarrito({
    required this.productoId,
    required this.sku,
    required this.descripcion,
    required this.cantidad,
    required this.costoUnitario,
  });

  double get subtotal => cantidad * costoUnitario;
}

// ─────────────────────────────────────────────────────────────────────────────
class CrearOrdenCompraScreen extends StatefulWidget {
  const CrearOrdenCompraScreen({super.key});

  @override
  State<CrearOrdenCompraScreen> createState() => _CrearOrdenCompraScreenState();
}

class _CrearOrdenCompraScreenState extends State<CrearOrdenCompraScreen> {
  // ── Formatters ──────────────────────────────────────────────────────────
  static final NumberFormat _currFmt =
      NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  // ── Estado de carga de catálogos ────────────────────────────────────────
  bool _cargandoCatalogos = true;
  String? _errorCatalogos;

  // ── Catálogos ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _proveedores = [];
  List<Map<String, dynamic>> _tiendas = [];
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _productosFiltrados = [];

  // ── Selecciones del encabezado ──────────────────────────────────────────
  String? _proveedorId;
  String? _tiendaId;

  // ── Buscador de productos ───────────────────────────────────────────────
  final TextEditingController _busquedaCtrl = TextEditingController();

  // ── Carrito interno ─────────────────────────────────────────────────────
  final List<_ItemCarrito> _carrito = [];

  // ── Guardando ───────────────────────────────────────────────────────────
  bool _guardando = false;

  // ── Form key ────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
    _busquedaCtrl.addListener(_filtrarProductos);
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // ── Carga paralela de catálogos ─────────────────────────────────────────
  Future<void> _cargarCatalogos() async {
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('proveedores')
            .select('id, razon_social')
            .order('razon_social'),
        Supabase.instance.client
            .from('tiendas')
            .select('id, nombre')
            .order('nombre'),
        Supabase.instance.client
            .from('productos')
            .select('id, sku, descripcion_1, costo')
            .order('descripcion_1'),
      ]);

      if (!mounted) return;
      setState(() {
        _proveedores = List<Map<String, dynamic>>.from(results[0] as List);
        _tiendas = List<Map<String, dynamic>>.from(results[1] as List);
        _productos = List<Map<String, dynamic>>.from(results[2] as List);
        _productosFiltrados = _productos;
        _cargandoCatalogos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCatalogos = e.toString();
        _cargandoCatalogos = false;
      });
    }
  }

  /// Recarga únicamente el catálogo de proveedores y opcionalmente selecciona uno.
  Future<void> _recargarProveedores(String? seleccionarId) async {
    try {
      final res = await Supabase.instance.client
          .from('proveedores')
          .select('id, razon_social')
          .order('razon_social');
      if (!mounted) return;
      setState(() {
        _proveedores = List<Map<String, dynamic>>.from(res as List);
        if (seleccionarId != null) {
          _proveedorId = seleccionarId;
        }
      });
    } catch (_) {}
  }

  /// Abre un diálogo flotante para registrar un proveedor nuevo al vuelo.
  void _mostrarDialogoNuevoProveedor() {
    final formKey = GlobalKey<FormState>();
    final razonSocialCtrl = TextEditingController();
    final rucCtrl = TextEditingController();
    final contactoCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();
    bool dialogSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text(
              "Registrar Proveedor",
              style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogField(
                      controller: razonSocialCtrl,
                      label: "Razón Social *",
                      hint: "ej. Ferretería Industrial",
                      validator: (v) => v == null || v.trim().isEmpty
                          ? "Requerido"
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField(
                      controller: rucCtrl,
                      label: "RUC",
                      hint: "ej. 20123456789",
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField(
                      controller: contactoCtrl,
                      label: "Contacto",
                      hint: "Nombre representante",
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField(
                      controller: telefonoCtrl,
                      label: "Teléfono",
                      hint: "ej. 987654321",
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField(
                      controller: emailCtrl,
                      label: "Email",
                      hint: "ej. ventas@prov.com",
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField(
                      controller: direccionCtrl,
                      label: "Dirección",
                      hint: "Dirección fiscal",
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: dialogSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade400,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: dialogSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => dialogSaving = true);
                        try {
                          final nuevoProv = await Supabase.instance.client
                              .from('proveedores')
                              .insert({
                                'razon_social': razonSocialCtrl.text.trim(),
                                'ruc': rucCtrl.text.trim().isEmpty
                                    ? null
                                    : rucCtrl.text.trim(),
                                'contacto': contactoCtrl.text.trim().isEmpty
                                    ? null
                                    : contactoCtrl.text.trim(),
                                'telefono': telefonoCtrl.text.trim().isEmpty
                                    ? null
                                    : telefonoCtrl.text.trim(),
                                'email': emailCtrl.text.trim().isEmpty
                                    ? null
                                    : emailCtrl.text.trim(),
                                'direccion': direccionCtrl.text.trim().isEmpty
                                    ? null
                                    : direccionCtrl.text.trim(),
                              })
                              .select('id')
                              .single();

                          final nuevoId = nuevoProv['id']?.toString();
                          await _recargarProveedores(nuevoId);

                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Proveedor creado y seleccionado'),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            Navigator.pop(ctx);
                          }
                        } catch (e) {
                          setDialogState(() => dialogSaving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al crear: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                child: dialogSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _filtrarProductos() {
    final q = _busquedaCtrl.text.toLowerCase();
    setState(() {
      _productosFiltrados = q.isEmpty
          ? _productos
          : _productos.where((p) {
              final desc =
                  (p['descripcion_1'] as String? ?? '').toLowerCase();
              final sku = (p['sku'] as String? ?? '').toLowerCase();
              return desc.contains(q) || sku.contains(q);
            }).toList();
    });
  }

  // ── Total del carrito ───────────────────────────────────────────────────
  double get _total => _carrito.fold(0, (sum, i) => sum + i.subtotal);

  // ── Diálogo para agregar producto ───────────────────────────────────────
  void _mostrarDialogoAgregarProducto(Map<String, dynamic> producto) {
    final cantCtrl = TextEditingController(text: '1');
    final costoCtrl = TextEditingController(
      text: (producto['costo'] != null)
          ? double.tryParse(producto['costo'].toString())
                  ?.toStringAsFixed(2) ??
              ''
          : '',
    );
    final dKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          producto['descripcion_1'] as String? ?? 'Producto',
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: Form(
          key: dKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SKU: ${producto['sku'] ?? '—'}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _buildDialogField(
                controller: cantCtrl,
                label: 'Cantidad',
                hint: 'ej. 5',
                isDecimal: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if ((double.tryParse(v) ?? 0) <= 0) {
                    return 'Debe ser mayor a 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildDialogField(
                controller: costoCtrl,
                label: 'Costo unitario',
                hint: 'ej. 120.50',
                isDecimal: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if ((double.tryParse(v) ?? -1) < 0) {
                    return 'Valor inválido';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade400,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (!dKey.currentState!.validate()) return;
              final cant = double.parse(cantCtrl.text);
              final costo = double.parse(costoCtrl.text);

              // Actualiza si ya existe en el carrito, sino agrega
              final idx = _carrito.indexWhere(
                  (i) => i.productoId == producto['id'].toString());
              setState(() {
                if (idx >= 0) {
                  _carrito[idx].cantidad += cant;
                  _carrito[idx].costoUnitario = costo;
                } else {
                  _carrito.add(_ItemCarrito(
                    productoId: producto['id'].toString(),
                    sku: producto['sku'] as String? ?? '',
                    descripcion:
                        producto['descripcion_1'] as String? ?? '',
                    cantidad: cant,
                    costoUnitario: costo,
                  ));
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isDecimal = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: false),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Colors.tealAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
      ),
      validator: validator,
    );
  }

  // ── Guardar orden en Supabase ────────────────────────────────────────────
  Future<void> _guardarOrden() async {
    if (!_formKey.currentState!.validate()) return;
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un producto al carrito'),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final userId =
          Supabase.instance.client.auth.currentUser?.id;

      // 1. Insertar cabecera en ordenes_compra
      final ordenResp = await Supabase.instance.client
          .from('ordenes_compra')
          .insert({
            'proveedor_id': _proveedorId,
            'tienda_id': _tiendaId,
            'usuario_id': userId,
            'estado': 'borrador',
            'monto_total': _total,
            'fecha_orden': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();

      final ordenId = ordenResp['id'];

      // 2. Insertar detalles
      final detalles = _carrito
          .map((item) => {
                'orden_compra_id': ordenId,
                'producto_id': item.productoId,
                'cantidad': item.cantidad,
                'costo_unitario': item.costoUnitario,
                'subtotal': item.subtotal,
              })
          .toList();

      await Supabase.instance.client
          .from('detalles_orden_compra')
          .insert(detalles);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Orden de compra guardada correctamente'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true); // true = recargar dashboard
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Nueva Orden de Compra',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (!_cargandoCatalogos && _errorCatalogos == null)
            _guardando
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.tealAccent),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _guardarOrden,
                    icon: const Icon(Icons.save_outlined,
                        color: Colors.tealAccent, size: 18),
                    label: const Text(
                      'Guardar',
                      style: TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
        ],
      ),
      body: _cargandoCatalogos
          ? const Center(
              child:
                  CircularProgressIndicator(color: Colors.tealAccent))
          : _errorCatalogos != null
              ? _buildError()
              : _buildForm(),
    );
  }

  // ── Error de catálogos ───────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            'Error cargando datos:\n$_errorCatalogos',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _cargandoCatalogos = true;
                _errorCatalogos = null;
              });
              _cargarCatalogos();
            },
            icon: const Icon(Icons.refresh, color: Colors.tealAccent),
            label: const Text('Reintentar',
                style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
  }

  // ── Formulario principal ─────────────────────────────────────────────────
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              children: [
                // ── Encabezado ────────────────────────────────────────────
                _sectionTitle('Encabezado'),
                const SizedBox(height: 10),
                _buildDropdownProveedor(),
                const SizedBox(height: 12),
                _buildDropdownTienda(),
                const SizedBox(height: 20),

                // ── Buscador de productos ─────────────────────────────────
                _sectionTitle('Agregar Productos'),
                const SizedBox(height: 10),
                _buildBuscador(),
                const SizedBox(height: 8),
                if (_busquedaCtrl.text.isNotEmpty)
                  _buildListaProductosBusqueda(),

                // ── Carrito ───────────────────────────────────────────────
                if (_carrito.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('Carrito (${_carrito.length})'),
                  const SizedBox(height: 8),
                  ..._carrito.map((item) => _buildItemCarrito(item)),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),

          // ── Barra total ───────────────────────────────────────────────────
          _buildBarraTotal(),
        ],
      ),
    );
  }

  // ── Sección título ──────────────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.tealAccent,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  // ── Dropdown Proveedor ──────────────────────────────────────────────────
  Widget _buildDropdownProveedor() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _proveedorId,
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            iconEnabledColor: Colors.white54,
            decoration: _inputDecoration('Proveedor', Icons.business_outlined),
            items: _proveedores.map((p) {
              return DropdownMenuItem<String>(
                value: p['id'].toString(),
                child: Text(
                  p['razon_social'] as String? ?? '—',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (v) => setState(() => _proveedorId = v),
            validator: (v) => v == null ? 'Selecciona un proveedor' : null,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _mostrarDialogoNuevoProveedor,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.all(14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.tealAccent.withOpacity(0.3)),
            ),
          ),
          icon: const Icon(Icons.add, color: Colors.tealAccent),
          tooltip: 'Registrar Proveedor al vuelo',
        ),
      ],
    );
  }

  // ── Dropdown Tienda ─────────────────────────────────────────────────────
  Widget _buildDropdownTienda() {
    return DropdownButtonFormField<String>(
      value: _tiendaId,
      dropdownColor: const Color(0xFF2A2A2A),
      style: const TextStyle(color: Colors.white),
      iconEnabledColor: Colors.white54,
      decoration: _inputDecoration('Tienda de destino', Icons.store_outlined),
      items: _tiendas.map((t) {
        return DropdownMenuItem<String>(
          value: t['id'].toString(),
          child: Text(
            t['nombre'] as String? ?? '—',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() => _tiendaId = v),
      validator: (v) => v == null ? 'Selecciona una tienda' : null,
    );
  }

  // ── Buscador de productos ───────────────────────────────────────────────
  Widget _buildBuscador() {
    return TextField(
      controller: _busquedaCtrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Buscar producto por nombre o SKU…',
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white38),
        suffixIcon: _busquedaCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.white38),
                onPressed: () {
                  _busquedaCtrl.clear();
                  FocusScope.of(context).unfocus();
                },
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Colors.tealAccent, width: 1.5),
        ),
      ),
    );
  }

  // ── Lista de resultados de búsqueda ─────────────────────────────────────
  Widget _buildListaProductosBusqueda() {
    if (_productosFiltrados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Sin resultados',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    final mostrar = _productosFiltrados.take(8).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: mostrar.map((p) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.inventory_2_outlined,
                color: Colors.tealAccent, size: 18),
            title: Text(
              p['descripcion_1'] as String? ?? '—',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'SKU: ${p['sku'] ?? '—'}  ·  Costo: ${_currFmt.format(double.tryParse(p['costo']?.toString() ?? '0') ?? 0)}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            trailing: const Icon(Icons.add_circle_outline,
                color: Colors.tealAccent, size: 20),
            onTap: () {
              FocusScope.of(context).unfocus();
              _mostrarDialogoAgregarProducto(p);
            },
          );
        }).toList(),
      ),
    );
  }

  // ── Ítem del carrito ────────────────────────────────────────────────────
  Widget _buildItemCarrito(_ItemCarrito item) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          item.descripcion,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'SKU: ${item.sku}  ·  ${item.cantidad % 1 == 0 ? item.cantidad.toInt() : item.cantidad} × ${_currFmt.format(item.costoUnitario)}',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currFmt.format(item.subtotal),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () =>
                  setState(() => _carrito.remove(item)),
              child: const Icon(Icons.remove_circle_outline,
                  color: Colors.redAccent, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barra total inferior ─────────────────────────────────────────────────
  Widget _buildBarraTotal() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_carrito.length} producto${_carrito.length != 1 ? 's' : ''}',
            style:
                const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          Row(
            children: [
              const Text('TOTAL  ',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              Text(
                _currFmt.format(_total),
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Decoración de inputs ─────────────────────────────────────────────────
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      filled: true,
      fillColor: const Color(0xFF1E1E1E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.tealAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
    );
  }
}
