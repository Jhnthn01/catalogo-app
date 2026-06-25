import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/features/orders/mis_pedidos_page.dart';
import 'package:catalogo_digital_app/features/orders/order_pdf_helper.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';
import 'package:printing/printing.dart';

class CarritoPage extends StatefulWidget {
  const CarritoPage({super.key});

  @override
  State<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends State<CarritoPage> {
  final cart = CartService();

  final TextEditingController _nombreClienteController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();
  final TextEditingController _tipoDocumentoController = TextEditingController(text: 'DNI');
  final TextEditingController _numeroDocumentoController = TextEditingController();
  final TextEditingController _telefonoClienteController = TextEditingController();
  final TextEditingController _tipoComprobanteController = TextEditingController(text: 'Boleta');
  final TextEditingController _formaPagoController = TextEditingController(text: 'Efectivo');
  final TextEditingController _segundoRecogeController = TextEditingController();
  final TextEditingController _fechaDateController = TextEditingController();
  TimeOfDay? _horaEntrega;

  bool _isPagoCombinado = false;
  final List<Map<String, dynamic>> _pagosCombinados = [
    {'metodo': 'Efectivo', 'montoController': TextEditingController()}
  ];

  @override
  void dispose() {
    _nombreClienteController.dispose();
    _direccionController.dispose();
    _tipoDocumentoController.dispose();
    _numeroDocumentoController.dispose();
    _telefonoClienteController.dispose();
    _tipoComprobanteController.dispose();
    _formaPagoController.dispose();
    _segundoRecogeController.dispose();
    _fechaDateController.dispose();
    for (var p in _pagosCombinados) {
      (p['montoController'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _refrescar() => setState(() {});

  Future<void> _confirmarPedido() async {
    if (cart.items.isEmpty) return;

    final nombreCliente = _nombreClienteController.text.trim();
    final direccionCliente = _direccionController.text.trim();
    final numeroDocumento = _numeroDocumentoController.text.trim();
    final telefonoCliente = _telefonoClienteController.text.trim();
    final dateStr = _fechaDateController.text.trim();

    if (nombreCliente.isEmpty || direccionCliente.isEmpty || numeroDocumento.isEmpty || telefonoCliente.isEmpty || dateStr.isEmpty || _horaEntrega == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: Nombre, Dirección, Nro. Documento, Teléfono, fecha y hora son obligatorios"),
          backgroundColor: Colors.redAccent,
      ));
      return;
    }

    if (telefonoCliente.length != 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: El teléfono debe tener 9 dígitos"),
          backgroundColor: Colors.redAccent,
      ));
      return;
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
      
      if (suma.toStringAsFixed(2) != cart.total.toStringAsFixed(2)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Error: La suma de los pagos debe coincidir con el total del pedido"),
            backgroundColor: Colors.redAccent,
        ));
        return;
      }
      formaPagoFinal = partes.join(" | ");
    } else {
      formaPagoFinal = _formaPagoController.text.trim();
    }

    DateTime parsedDate;
    try {
      parsedDate = DateFormat('dd/MM/yyyy').parseStrict(dateStr);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: Formato inválido (dd/mm/yyyy) o fecha inexistente"),
          backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (parsedDate.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: La fecha no puede ser en el pasado"),
          backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final DateTime fechaEntregaFinal = DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      _horaEntrega!.hour,
      _horaEntrega!.minute,
    );

    try {
      final user = Supabase.instance.client.auth.currentUser;

      bool requiereRegularizacion = false;
      for (var item in cart.items) {
        if (item.cantidad > item.stockActual) {
          requiereRegularizacion = true;
          break;
        }
      }

      final pedido = await Supabase.instance.client.from('pedidos').insert({
        'usuario_id': user!.id,
        'total': cart.total,
        'estado': 'pendiente',
        'nombre_cliente': nombreCliente,
        'direccion_cliente': direccionCliente,
        'tipo_documento': _tipoDocumentoController.text.trim(),
        'numero_documento': numeroDocumento,
        'telefono_cliente': telefonoCliente,
        'tipo_comprobante': _tipoComprobanteController.text.trim(),
        'forma_pago': formaPagoFinal,
        'fecha_entrega': fechaEntregaFinal.toUtc().toIso8601String(),
        'segundo_recoge': _segundoRecogeController.text.trim().isNotEmpty ? _segundoRecogeController.text.trim() : null,
        'requiere_regularizacion': requiereRegularizacion,
        'tienda_id': TiendaService().tiendaActivaId.value,
      }).select().single();

      final detalles = cart.items
          .map((item) => {
                'pedido_id': pedido['id'],
                'producto_id': item.id,
                'cantidad': item.cantidad,
                'precio_unitario': item.precio,
              })
          .toList();

      await Supabase.instance.client.from('detalles_pedido').insert(detalles);

      final itemsConfirmados = List<CartItem>.from(cart.items);
      cart.limpiar();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("¡Pedido registrado con éxito! Pendiente de despacho.", style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
        await _mostrarDialogoImpresion(pedido, itemsConfirmados);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _mostrarDialogoImpresion(Map<String, dynamic> pedido, List<CartItem> itemsConfirmados) async {
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
                  Text("¿Imprimir o descargar?", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "El pedido ha sido registrado con éxito. Elija el formato del comprobante para proceder:",
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
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text("CERRAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.send, size: 16, color: Colors.white),
                  label: const Text("WhatsApp", style: TextStyle(color: Colors.white)),
                  onPressed: () => OrderPdfHelper.enviarWhatsApp(dialogContext, pedido),
                ),
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
                              bytes = await OrderPdfHelper.generateA4(pedido: pedido, items: itemsConfirmados);
                            } else {
                              bytes = await OrderPdfHelper.generateTicket(pedido: pedido, items: itemsConfirmados);
                            }
                            final idCorto = pedido['id'].toString().substring(0, 8).toUpperCase();
                            await Printing.sharePdf(bytes: bytes, filename: 'pedido_$idCorto.pdf');
                          } catch (e) {
                            debugPrint("Error sharing pdf: $e");
                          } finally {
                            setDialogState(() => isGenerating = false);
                          }
                        },
                ),
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
                              bytes = await OrderPdfHelper.generateA4(pedido: pedido, items: itemsConfirmados);
                            } else {
                              bytes = await OrderPdfHelper.generateTicket(pedido: pedido, items: itemsConfirmados);
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
            );
          },
        );
      },
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MisPedidosPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Resumen de Pedido"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: cart.items.isEmpty
          ? _buildCarritoVacio()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(15),
                    children: [
                      ...cart.items.map((item) => _buildCartItem(item)),
                      const SizedBox(height: 20),
                      const Text("Datos del Pedido", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      _buildTextField("Nombre del Cliente *", _nombreClienteController),
                      const SizedBox(height: 10),
                      _buildTextField("Dirección del Cliente Titular *", _direccionController),
                      const SizedBox(height: 10),
                      _buildDropdown("Tipo de Documento", _tipoDocumentoController, ['DNI', 'RUC', 'CE']),
                      const SizedBox(height: 10),
                      _buildTextFieldNum("Número de Documento *", _numeroDocumentoController),
                      const SizedBox(height: 10),
                      _buildTextFieldNumLength("Teléfono del Cliente *", _telefonoClienteController, 9),
                      const SizedBox(height: 10),
                      _buildDropdown("Tipo de Comprobante", _tipoComprobanteController, ['Boleta', 'Factura', 'Nota de Venta']),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Forma de Pago", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                              selectedBackgroundColor: Colors.blue.withOpacity(0.3),
                              foregroundColor: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!_isPagoCombinado)
                        _buildDropdown("Método de Pago", _formaPagoController, ['Efectivo', 'Tarjeta de Crédito/Débito', 'Yape', 'Plin', 'Transferencia Bancaria', 'Crédito'])
                      else
                        _buildPagoCombinado(),
                      const SizedBox(height: 10),
                      _buildTextField("Segundo a Recoger (Opcional)", _segundoRecogeController),
                      const SizedBox(height: 10),
                      _buildDateTimePicker(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
    );
  }

  Widget _buildCarritoVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.remove_shopping_cart_outlined,
              size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 15),
          const Text("Tu carrito está vacío",
              style: TextStyle(color: Colors.grey, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildTextFieldNum(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildTextFieldNumLength(String label, TextEditingController controller, int length) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ],
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildDropdown(String label, TextEditingController controller, List<String> options) {
    return DropdownButtonFormField<String>(
      value: controller.text.isNotEmpty ? controller.text : options.first,
      dropdownColor: const Color(0xFF2C2C2C),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
      items: options.map((opt) {
        return DropdownMenuItem(value: opt, child: Text(opt));
      }).toList(),
      onChanged: (val) {
        if (val != null) controller.text = val;
      },
    );
  }

  Widget _buildPagoCombinado() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: ['Efectivo', 'Tarjeta de Crédito/Débito', 'Yape', 'Plin', 'Transferencia Bancaria', 'Crédito'].map((opt) {
                        return DropdownMenuItem(value: opt, child: Text(opt, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _pagosCombinados[index]['metodo'] = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: pago['montoController'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Monto",
                        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF2C2C2C),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
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
                    const SizedBox(width: 48), // Spacer to keep alignment
                ],
              ),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.add, color: Colors.blue),
            label: const Text("Añadir Método", style: TextStyle(color: Colors.blue)),
            onPressed: () {
              setState(() {
                _pagosCombinados.add({
                  'metodo': 'Efectivo',
                  'montoController': TextEditingController()
                });
              });
            },
          )
        ],
      ),
    );
  }

  Widget _buildDateTimePicker() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _fechaDateController,
            keyboardType: TextInputType.datetime,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
              _DateTextFormatter(),
            ],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "Fecha (dd/mm/yyyy) *",
              labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_month, color: Colors.blue),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Colors.blue,
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
                    final formattedDate = DateFormat('dd/MM/yyyy').format(date);
                    _fechaDateController.text = formattedDate;
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () async {
              final List<TimeOfDay> allowedTimes = [];
              for (int h = 7; h <= 18; h++) {
                allowedTimes.add(TimeOfDay(hour: h, minute: 0));
                if (h < 18) allowedTimes.add(TimeOfDay(hour: h, minute: 30));
              }

              final time = await showDialog<TimeOfDay>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text("Hora (07:00 - 18:00)", style: TextStyle(color: Colors.white, fontSize: 16)),
                    content: SizedBox(
                      width: double.maxFinite,
                      height: 300,
                      child: ListView.builder(
                        itemCount: allowedTimes.length,
                        itemBuilder: (context, index) {
                          final t = allowedTimes[index];
                          final isAM = t.hour < 12;
                          final displayHour = t.hour == 12 ? 12 : t.hour % 12;
                          final hStr = displayHour == 0 ? "12" : displayHour.toString().padLeft(2, '0');
                          final mStr = t.minute.toString().padLeft(2, '0');
                          final amPm = isAM ? "AM" : "PM";
                          return ListTile(
                            title: Text("$hStr:$mStr $amPm", style: const TextStyle(color: Colors.white70)),
                            onTap: () => Navigator.pop(context, t),
                          );
                        },
                      ),
                    ),
                  );
                },
              );

              if (time != null) {
                setState(() => _horaEntrega = time);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _horaEntrega == null 
                        ? "Hora *" 
                        : "${_horaEntrega!.hour == 12 ? 12 : _horaEntrega!.hour % 12 == 0 ? 12 : _horaEntrega!.hour % 12}:${_horaEntrega!.minute.toString().padLeft(2, '0')} ${_horaEntrega!.hour < 12 ? 'AM' : 'PM'}",
                    style: TextStyle(color: _horaEntrega == null ? Colors.grey : Colors.white, fontSize: 13),
                  ),
                  const Icon(Icons.access_time, color: Colors.blue, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCartItem(CartItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 5),
                Text("S/.${item.precio.toStringAsFixed(2)} c/u",
                    style: const TextStyle(color: Colors.blue, fontSize: 14)),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.grey),
                onPressed: () {
                  cart.actualizarCantidad(item.id, item.cantidad - 1);
                  _refrescar();
                },
              ),
              GestureDetector(
                onTap: () async {
                  final TextEditingController qtyController =
                      TextEditingController(text: item.cantidad.toString());
                  await showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        backgroundColor: const Color(0xFF2C2C2C),
                        title: const Text("Editar Cantidad",
                            style: TextStyle(color: Colors.white)),
                        content: TextField(
                          controller: qtyController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue)),
                            enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.grey)),
                          ),
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("CANCELAR",
                                style: TextStyle(color: Colors.grey)),
                          ),
                          TextButton(
                            onPressed: () {
                              final int? newQty =
                                  int.tryParse(qtyController.text);
                              if (newQty != null && newQty >= 0) {
                                cart.actualizarCantidad(item.id, newQty);
                                _refrescar();
                              }
                              Navigator.pop(context);
                            },
                            child: const Text("GUARDAR",
                                style: TextStyle(color: Colors.blue)),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.blue.withOpacity(0.5))),
                  child: Text(
                    "${item.cantidad}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                onPressed: () {
                  cart.actualizarCantidad(item.id, item.cantidad + 1);
                  _refrescar();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  cart.eliminarProducto(item.id);
                  _refrescar();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total Estimado",
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                Text(
                  "S/.${cart.total.toStringAsFixed(2)}",
                  style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _confirmarPedido,
                child: const Text(
                  "CONFIRMAR MI PEDIDO",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;

    text = text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.length > 8) {
      text = text.substring(0, 8);
    }

    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 2 || i == 4) {
        formatted += '/';
      }
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
