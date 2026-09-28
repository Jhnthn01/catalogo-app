import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';

import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:catalogo_digital_app/features/orders/mis_pedidos_page.dart';
import 'package:catalogo_digital_app/features/orders/pedidos_entregados_page.dart';
import 'package:catalogo_digital_app/features/orders/order_pdf_helper.dart';

class CheckoutFormWidget extends StatefulWidget {
  final bool isConfirming;
  final ValueChanged<bool> onConfirmingChanged;
  final VoidCallback onVerCatalogoPressed;
  final VoidCallback onVentaExitosa;
  final Widget? productosAgregadosWidget;

  const CheckoutFormWidget({
    super.key,
    required this.isConfirming,
    required this.onConfirmingChanged,
    required this.onVerCatalogoPressed,
    required this.onVentaExitosa,
    this.productosAgregadosWidget,
  });

  @override
  State<CheckoutFormWidget> createState() => _CheckoutFormWidgetState();
}

class _CheckoutFormWidgetState extends State<CheckoutFormWidget> {
  final _supabase = Supabase.instance.client;

  // Sales Module variables
  bool _isEntrega = false;

  // Customer fields
  final TextEditingController _nombreClienteController = TextEditingController();
  final TextEditingController _telefonoClienteController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();
  final TextEditingController _fechaHoraController = TextEditingController();
  final TextEditingController _tipoDocumentoController = TextEditingController(text: 'DNI');
  final TextEditingController _numeroDocumentoController = TextEditingController();
  final TextEditingController _tipoComprobanteController = TextEditingController(text: 'Nota de Venta');
  final TextEditingController _formaPagoController = TextEditingController(text: 'Efectivo');
  final TextEditingController _segundoRecogeController = TextEditingController();
  DateTime? _fechaEntrega;
  TimeOfDay? _horaEntrega;

  // Payment mode
  bool _isPagoCombinado = false;
  final List<Map<String, dynamic>> _pagosCombinados = [
    {'metodo': 'Efectivo', 'montoController': TextEditingController()},
  ];

  @override
  void dispose() {
    _nombreClienteController.dispose();
    _telefonoClienteController.dispose();
    _direccionController.dispose();
    _fechaHoraController.dispose();
    _tipoDocumentoController.dispose();
    _numeroDocumentoController.dispose();
    _tipoComprobanteController.dispose();
    _formaPagoController.dispose();
    _segundoRecogeController.dispose();
    for (var p in _pagosCombinados) {
      (p['montoController'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _limpiarFormulario() {
    _nombreClienteController.clear();
    _telefonoClienteController.clear();
    _direccionController.clear();
    _fechaHoraController.clear();
    _numeroDocumentoController.clear();
    _segundoRecogeController.clear();
    _tipoDocumentoController.text = 'DNI';
    _tipoComprobanteController.text = 'Nota de Venta';
    _formaPagoController.text = 'Efectivo';
    _fechaEntrega = null;
    _horaEntrega = null;
    _isPagoCombinado = false;
    for (var p in _pagosCombinados) {
      (p['montoController'] as TextEditingController).dispose();
    }
    _pagosCombinados
      ..clear()
      ..add({'metodo': 'Efectivo', 'montoController': TextEditingController()});
    if (mounted) setState(() {});
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _confirmarPedido() async {
    final nombre = _nombreClienteController.text.trim();
    final telefono = _telefonoClienteController.text.trim();
    final items = CartService().items;

    if (nombre.isEmpty) {
      _showError("Por favor, ingresa el nombre del cliente.");
      return;
    }

    if (_isEntrega) {
      if (telefono.isEmpty) {
        _showError("Por favor, ingresa el teléfono del cliente para la entrega.");
        return;
      }
      if (telefono.length != 9) {
        _showError("El teléfono debe tener exactamente 9 dígitos.");
        return;
      }
    } else {
      if (telefono.isNotEmpty && telefono.length != 9) {
        _showError("El teléfono ingresado debe tener exactamente 9 dígitos.");
        return;
      }
    }

    String formaPagoFinal = '';

    if (_isPagoCombinado) {
      double suma = 0;
      List<String> partes = [];
      for (var p in _pagosCombinados) {
        final ctrl = p['montoController'] as TextEditingController;
        final monto = double.tryParse(ctrl.text.trim()) ?? 0.0;
        suma += monto;
        partes.add("${p['metodo']}: S/.${monto.toStringAsFixed(2)}");
      }
      if (suma.toStringAsFixed(2) != CartService().total.toStringAsFixed(2)) {
        _showError("La suma de los pagos (S/.${suma.toStringAsFixed(2)}) debe coincidir con el total del pedido (S/.${CartService().total.toStringAsFixed(2)}).");
        return;
      }
      formaPagoFinal = partes.join(" | ");
    } else {
      formaPagoFinal = _formaPagoController.text.trim();
    }

    if (_isEntrega) {
      if (_direccionController.text.trim().isEmpty) {
        _showError("Por favor, ingresa la dirección de entrega.");
        return;
      }
      final numDoc = _numeroDocumentoController.text.trim();
      if (numDoc.isEmpty) {
        _showError("Por favor, ingresa el número de documento.");
        return;
      }
      if (_fechaEntrega == null) {
        _showError("Por favor, selecciona la fecha y hora de entrega.");
        return;
      }
    }

    if (items.isEmpty) {
      _showError("Por favor, añade al menos un producto al pedido.");
      return;
    }

    widget.onConfirmingChanged(true);

    try {
      DateTime fechaEntregaFinal = DateTime.now();
      if (_isEntrega && _fechaEntrega != null && _horaEntrega != null) {
        fechaEntregaFinal = DateTime(
          _fechaEntrega!.year,
          _fechaEntrega!.month,
          _fechaEntrega!.day,
          _horaEntrega!.hour,
          _horaEntrega!.minute,
        );
      }

      final List<CartItem> itemsCopy = List.from(items);

      final resultado = await _supabase.rpc('confirmar_venta_catalogo', params: {
        'p_tienda_id': TiendaService().tiendaActivaId.value,
        'p_items': itemsCopy.map((item) => {
          'producto_id': item.id,
          'cantidad': item.cantidad,
          'precio_unitario': item.precio,
        }).toList(),
        'p_nombre_cliente': nombre,
        'p_telefono_cliente': telefono,
        'p_direccion_cliente': _isEntrega ? _direccionController.text.trim() : null,
        'p_tipo_documento': _isEntrega ? _tipoDocumentoController.text.trim() : null,
        'p_numero_documento': _isEntrega ? _numeroDocumentoController.text.trim() : null,
        'p_tipo_comprobante': _isEntrega ? _tipoComprobanteController.text.trim() : 'Nota de Venta',
        'p_forma_pago': formaPagoFinal,
        'p_fecha_entrega': fechaEntregaFinal.toUtc().toIso8601String(),
        'p_segundo_recoge': _isEntrega && _segundoRecogeController.text.trim().isNotEmpty
            ? _segundoRecogeController.text.trim()
            : null,
        'p_estado': _isEntrega ? 'pendiente' : 'entregado',
        'p_total': CartService().total,
        'p_descontar_stock': !_isEntrega,
      });

      final Map<String, dynamic> pedido = resultado != null && resultado['pedido'] != null
          ? Map<String, dynamic>.from(resultado['pedido'])
          : {'id': resultado?['pedido_id']};

      widget.onVentaExitosa();
      _limpiarFormulario();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("¡Pedido registrado con éxito!", style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (_isEntrega) {
        try {
          final bytes = await OrderPdfHelper.generateTicket(pedido: pedido, items: itemsCopy);
          Printing.layoutPdf(onLayout: (format) async => bytes);
        } catch (e) {
          debugPrint("Error auto-printing ticket: $e");
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MisPedidosPage()),
          );
        }
      } else {
        if (mounted) {
          await _mostrarDialogoImpresionVentaTienda(pedido, itemsCopy);
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PedidosEntregadosPage()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al registrar pedido: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        widget.onConfirmingChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              // Header section
              SliverToBoxAdapter(child: _buildHeader()),

              // Customer fields
              SliverToBoxAdapter(child: _buildCustomerFields()),

              // Card "Ver Catálogo"
              SliverToBoxAdapter(child: _buildVerCatalogCard()),

              // Added products section
              if (widget.productosAgregadosWidget != null)
                SliverToBoxAdapter(child: widget.productosAgregadosWidget!),

              // Bottom spacing
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
        _buildConfirmationFooter(),
      ],
    );
  }

  Widget _buildVerCatalogCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        color: const Color(0xFF1E1E1E),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Colors.blueAccent.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: widget.onVerCatalogoPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: const Text(
              "Ver Productos (Ventas)",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isEntrega = !_isEntrega;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSwitchOption("En Tienda", !_isEntrega),
                          _buildSwitchOption("Entrega", _isEntrega),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildStoreBadge(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _isEntrega ? "Venta por Entrega" : "Venta en Tienda",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreBadge() {
    final rol = (TiendaService().usuarioRol ?? '').toLowerCase();
    final bool esAdminOGerente = rol == 'admin' || rol == 'administrador' || rol == 'gerente';

    return ValueListenableBuilder<int?>(
      valueListenable: TiendaService().tiendaActivaId,
      builder: (context, tiendaId, child) {
        final tiendaNombre = TiendaService().tiendas.firstWhere(
          (t) => t['id'] == tiendaId,
          orElse: () => {'nombre': 'Sin Tienda'},
        )['nombre'] as String;

        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: esAdminOGerente
                  ? Colors.blueAccent.withValues(alpha: 0.5)
                  : Colors.blueAccent.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.store_rounded, color: Colors.blueAccent, size: 16),
              const SizedBox(width: 4),
              Text(
                tiendaNombre,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              if (esAdminOGerente) ...[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.blueAccent, size: 16),
              ],
            ],
          ),
        );

        if (!esAdminOGerente) return badge;

        return PopupMenuButton<int>(
          onSelected: (int id) {
            TiendaService().seleccionarTienda(id);
          },
          color: const Color(0xFF2C2C2C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (context) {
            return TiendaService().tiendas.map((t) {
              return PopupMenuItem<int>(
                value: t['id'] as int,
                child: Row(
                  children: [
                    Icon(
                      t['id'] == tiendaId ? Icons.check : Icons.store_outlined,
                      color: t['id'] == tiendaId ? Colors.blueAccent : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t['nombre'] as String,
                      style: TextStyle(
                        color: t['id'] == tiendaId ? Colors.blueAccent : Colors.white,
                        fontWeight: t['id'] == tiendaId ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: badge,
        );
      },
    );
  }

  Widget _buildSwitchOption(String title, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.blueAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: active ? Colors.white : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  // ─── Customer Fields ────────────────────────────────────────────────────────
  Widget _buildCustomerFields() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _nombreClienteController,
                  label: "Nombre del Cliente *",
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _telefonoClienteController,
                  label: _isEntrega ? "Teléfono *" : "Teléfono (Opcional)",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Forma de Pago",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('Único', style: TextStyle(fontSize: 12))),
                  ButtonSegment<bool>(value: true, label: Text('Combinado', style: TextStyle(fontSize: 12))),
                ],
                selected: {_isPagoCombinado},
                onSelectionChanged: (Set<bool> newSelection) {
                  setState(() {
                    _isPagoCombinado = newSelection.first;
                  });
                },
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  selectedForegroundColor: Colors.white,
                  selectedBackgroundColor: Colors.blueAccent.withValues(alpha: 0.3),
                  foregroundColor: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_isPagoCombinado)
            _buildDropdownField(
              controller: _formaPagoController,
              label: "Método de Pago",
              icon: Icons.payments_outlined,
              options: ['Efectivo', 'Tarjeta de Crédito/Débito', 'Yape', 'Plin', 'Transferencia Bancaria', 'Crédito'],
            )
          else
            _buildPagoCombinado(),

          if (_isEntrega) ...[
            const SizedBox(height: 12),
            _buildTextField(
              controller: _direccionController,
              label: "Dirección de Entrega *",
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildDropdownField(
                    controller: _tipoDocumentoController,
                    label: "Tipo Doc.",
                    icon: Icons.badge_outlined,
                    options: ['DNI', 'RUC', 'CE'],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    controller: _numeroDocumentoController,
                    label: "Número de Documento *",
                    icon: Icons.numbers_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDropdownField(
              controller: _tipoComprobanteController,
              label: "Tipo de Comprobante",
              icon: Icons.receipt_long_outlined,
              options: ['Nota de Venta', 'Boleta', 'Factura'],
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _segundoRecogeController,
              label: "Segundo a Recoger (Opcional)",
              icon: Icons.people_outline,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _seleccionarFechaHora,
              child: AbsorbPointer(
                child: _buildTextField(
                  controller: _fechaHoraController,
                  label: "Fecha/Hora de Entrega *",
                  icon: Icons.calendar_month_outlined,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 18),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required List<String> options,
  }) {
    return DropdownButtonFormField<String>(
      value: options.contains(controller.text) ? controller.text : options.first,
      dropdownColor: const Color(0xFF2C2C2C),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 18),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
      ),
      items: options.map((opt) {
        return DropdownMenuItem(value: opt, child: Text(opt));
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          controller.text = val;
          setState(() {});
        }
      },
    );
  }

  Widget _buildPagoCombinado() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          ..._pagosCombinados.asMap().entries.map((entry) {
            final index = entry.key;
            final pago = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: pago['metodo'],
                      dropdownColor: const Color(0xFF2C2C2C),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2C2C2C),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: ['Efectivo', 'Tarjeta de Crédito/Débito', 'Yape', 'Plin', 'Transferencia Bancaria', 'Crédito']
                          .map((opt) => DropdownMenuItem(
                                value: opt,
                                child: Text(opt, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _pagosCombinados[index]['metodo'] = val;
                            if (val == 'Tarjeta de Crédito/Débito' || val == 'Transferencia Bancaria') {
                              (pago['montoController'] as TextEditingController).text = CartService().total.toStringAsFixed(2);
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Builder(
                      builder: (context) {
                        final ctrl = pago['montoController'] as TextEditingController;
                        if (ctrl.text.isEmpty) {
                          ctrl.text = CartService().total.toStringAsFixed(2);
                        }
                        final isBlocked = pago['metodo'] == 'Tarjeta de Crédito/Débito' || pago['metodo'] == 'Transferencia Bancaria';
                        if (isBlocked) {
                          ctrl.text = CartService().total.toStringAsFixed(2);
                        }
                        return TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          readOnly: isBlocked,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Monto S/.",
                            labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF2C2C2C),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_pagosCombinados.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          (pago['montoController'] as TextEditingController).dispose();
                          _pagosCombinados.removeAt(index);
                        });
                      },
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.add, color: Colors.blueAccent),
            label: const Text("Añadir Método", style: TextStyle(color: Colors.blueAccent)),
            onPressed: () {
              setState(() {
                _pagosCombinados.add({
                  'metodo': 'Efectivo',
                  'montoController': TextEditingController(),
                });
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarFechaHora() async {
    final DateTime hoy = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _fechaEntrega ?? hoy,
      firstDate: hoy,
      lastDate: hoy.add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      if (!mounted) return;

      final List<TimeOfDay> slots = [];
      for (int h = 6; h <= 22; h++) {
        slots.add(TimeOfDay(hour: h, minute: 0));
        if (h < 22) slots.add(TimeOfDay(hour: h, minute: 30));
      }

      final TimeOfDay? time = await showDialog<TimeOfDay>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.access_time, color: Colors.blueAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  "Hora de Entrega",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: ListView.builder(
                itemCount: slots.length,
                itemBuilder: (ctx2, i) {
                  final t = slots[i];
                  final h12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
                  final ampm = t.hour < 12 ? 'AM' : 'PM';
                  final label = '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $ampm';
                  final isSelected = _horaEntrega?.hour == t.hour && _horaEntrega?.minute == t.minute;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedColor: Colors.blueAccent,
                    selectedTileColor: Colors.blueAccent.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    leading: Icon(
                      Icons.schedule,
                      color: isSelected ? Colors.blueAccent : Colors.grey,
                      size: 18,
                    ),
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.blueAccent : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, t),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      );

      if (time != null && mounted) {
        final h12 = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
        final ampm = time.hour < 12 ? 'AM' : 'PM';
        final timeLabel = '${h12.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $ampm';
        setState(() {
          _fechaEntrega = date;
          _horaEntrega = time;
          _fechaHoraController.text =
              "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} $timeLabel";
        });
      }
    }
  }

  // ─── Confirmation Footer ─────────────────────────────────────────────────────
  Widget _buildConfirmationFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Total Estimado:",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: CartService().itemsCountNotifier,
                  builder: (context, count, child) {
                    return Text(
                      "S/.${CartService().total.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
              ),
              onPressed: widget.isConfirming ? null : _confirmarPedido,
              child: widget.isConfirming
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "CONFIRMAR MI PEDIDO",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoImpresionVentaTienda(Map<String, dynamic> pedidoData, List<CartItem> itemsImpresion) async {
    String formatoSeleccionado = 'ticket';
    bool isGenerating = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Row(
                children: [
                  Icon(Icons.print_outlined, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Text("Impresión de Comprobante", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Elija el formato del comprobante para proceder:",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text("Ticketera (80mm)", style: TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: const Text("Formato compacto térmico", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          value: 'ticket',
                          groupValue: formatoSeleccionado,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => formatoSeleccionado = val);
                            }
                          },
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        RadioListTile<String>(
                          title: const Text("Hoja A4", style: TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: const Text("Diseño corporativo formal", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          value: 'a4',
                          groupValue: formatoSeleccionado,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => formatoSeleccionado = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  if (isGenerating) ...[
                    const SizedBox(height: 15),
                    const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text("Generando PDF...", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.send, size: 16, color: Colors.white),
                            label: const Text("WhatsApp", style: TextStyle(color: Colors.white)),
                            onPressed: () => OrderPdfHelper.enviarWhatsApp(dialogContext, pedidoData),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.download, size: 16, color: Colors.white),
                            label: const Text("PDF", style: TextStyle(color: Colors.white)),
                            onPressed: isGenerating
                                ? null
                                : () async {
                                    setDialogState(() => isGenerating = true);
                                    try {
                                      Uint8List bytes;
                                      if (formatoSeleccionado == 'a4') {
                                        bytes = await OrderPdfHelper.generateA4(pedido: pedidoData, items: itemsImpresion);
                                      } else {
                                        bytes = await OrderPdfHelper.generateTicket(pedido: pedidoData, items: itemsImpresion);
                                      }
                                      final idCorto = pedidoData['id'].toString().substring(0, 8).toUpperCase();
                                      await Printing.sharePdf(bytes: bytes, filename: 'pedido_$idCorto.pdf');
                                    } catch (e) {
                                      debugPrint("Error sharing pdf: $e");
                                    } finally {
                                      setDialogState(() => isGenerating = false);
                                    }
                                  },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.print, size: 16, color: Colors.white),
                            label: const Text("IMPRIMIR", style: TextStyle(color: Colors.white)),
                            onPressed: isGenerating
                                ? null
                                : () async {
                                    setDialogState(() => isGenerating = true);
                                    try {
                                      Uint8List bytes;
                                      if (formatoSeleccionado == 'a4') {
                                        bytes = await OrderPdfHelper.generateA4(pedido: pedidoData, items: itemsImpresion);
                                      } else {
                                        bytes = await OrderPdfHelper.generateTicket(pedido: pedidoData, items: itemsImpresion);
                                      }
                                      await Printing.layoutPdf(onLayout: (format) async => bytes);
                                    } catch (e) {
                                      debugPrint("Error printing: $e");
                                    } finally {
                                      setDialogState(() => isGenerating = false);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.pop(dialogContext);
                      },
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(15),
                        bottomRight: Radius.circular(15),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(15),
                            bottomRight: Radius.circular(15),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          "FINALIZAR",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
