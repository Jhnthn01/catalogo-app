import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NuevoProductoPage extends StatefulWidget {
  final String? initialSku;
  const NuevoProductoPage({super.key, this.initialSku});

  @override
  State<NuevoProductoPage> createState() => _NuevoProductoPageState();
}

class _NuevoProductoPageState extends State<NuevoProductoPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _upcController = TextEditingController();
  final TextEditingController _aluController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _categoriaController = TextEditingController();
  final TextEditingController _claseController = TextEditingController();
  final TextEditingController _subClaseController = TextEditingController();
  final TextEditingController _estiloController = TextEditingController();
  final TextEditingController _descripcion1Controller = TextEditingController();
  final TextEditingController _descripcion2Controller = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _costoController = TextEditingController();
  final TextEditingController _precioVentaController = TextEditingController();

  final MobileScannerController _scannerController = MobileScannerController();
  bool _isScanningSku = false;
  bool _isLoading = false;
  bool _isCheckingSku = false;
  String? _skuExistenteNombre;
  String? _ultimoSkuVerificado;

  @override
  void initState() {
    super.initState();
    if (widget.initialSku != null && widget.initialSku!.trim().isNotEmpty) {
      _skuController.text = widget.initialSku!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verificarSkuExistente(_skuController.text.trim());
      });
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _skuController.dispose();
    _upcController.dispose();
    _aluController.dispose();
    _marcaController.dispose();
    _categoriaController.dispose();
    _claseController.dispose();
    _subClaseController.dispose();
    _estiloController.dispose();
    _descripcion1Controller.dispose();
    _descripcion2Controller.dispose();
    _colorController.dispose();
    _costoController.dispose();
    _precioVentaController.dispose();
    super.dispose();
  }

  Future<bool> _verificarSkuExistente(String sku) async {
    final s = sku.trim();
    if (s.isEmpty) {
      if (mounted) {
        setState(() {
          _skuExistenteNombre = null;
          _ultimoSkuVerificado = null;
        });
      }
      return false;
    }

    if (s == _ultimoSkuVerificado && _skuExistenteNombre != null) {
      _mostrarAlertaSkuDuplicado(s, _skuExistenteNombre!);
      return true;
    }

    setState(() => _isCheckingSku = true);

    try {
      final res = await Supabase.instance.client
          .from('productos')
          .select('id, sku, descripcion_1')
          .eq('sku', s)
          .maybeSingle();

      if (!mounted) return false;

      _ultimoSkuVerificado = s;

      if (res != null) {
        final nombre = res['descripcion_1']?.toString() ?? 'Producto existente';
        setState(() {
          _skuExistenteNombre = nombre;
        });
        _mostrarAlertaSkuDuplicado(s, nombre);
        return true;
      } else {
        setState(() {
          _skuExistenteNombre = null;
        });
        return false;
      }
    } catch (e) {
      debugPrint('Error al verificar SKU existente: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isCheckingSku = false);
    }
  }

  void _mostrarAlertaSkuDuplicado(String sku, String nombreProducto) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.amber, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'SKU Ya Registrado',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            children: [
              const TextSpan(text: 'El SKU '),
              TextSpan(
                text: '"$sku"',
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: ' ya pertenece a otro producto en el inventario:\n\n'),
              TextSpan(
                text: '📦 $nombreProducto\n\n',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const TextSpan(text: 'Por favor, ingresa un código SKU diferente para este producto.'),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarProducto() async {
    if (!_formKey.currentState!.validate()) return;

    final String sku = _skuController.text.trim();
    final bool yaExiste = await _verificarSkuExistente(sku);
    if (yaExiste) return;

    setState(() => _isLoading = true);

    try {
      final double costo = double.tryParse(_costoController.text) ?? 0.0;
      final double precio = double.tryParse(_precioVentaController.text) ?? 0.0;

      final nowIso = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client.from('productos').insert({
        'sku': sku,
        'upc': _upcController.text.trim().isEmpty ? null : _upcController.text.trim(),
        'alu': _aluController.text.trim().isEmpty ? null : _aluController.text.trim(),
        'marca': _marcaController.text.trim().isEmpty ? null : _marcaController.text.trim(),
        'categoria': _categoriaController.text.trim().isEmpty ? null : _categoriaController.text.trim(),
        'clase': _claseController.text.trim().isEmpty ? null : _claseController.text.trim(),
        'sub_clase': _subClaseController.text.trim().isEmpty ? null : _subClaseController.text.trim(),
        'estilo': _estiloController.text.trim().isEmpty ? null : _estiloController.text.trim(),
        'descripcion_1': _descripcion1Controller.text.trim(),
        'descripcion_2': _descripcion2Controller.text.trim().isEmpty ? null : _descripcion2Controller.text.trim(),
        'color': _colorController.text.trim().isEmpty ? null : _colorController.text.trim(),
        'costo': costo,
        'precio_venta': precio,
        'ultimo_costo': costo,
        'costo_medio': costo,
        'fecha_ultimo_costo': costo > 0 ? nowIso : null,
        'modificado_por': Supabase.instance.client.auth.currentUser?.id,
        'modificado_at': nowIso,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto creado exitosamente', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // Devuelve true para recargar lista
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear producto: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildScannerBox() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String code = (barcodes.first.rawValue ?? "").trim();
                  if (code.isNotEmpty) {
                    setState(() {
                      _isScanningSku = false;
                      _skuController.text = code;
                    });
                    _verificarSkuExistente(code);
                  }
                }
              },
            ),
            Positioned(
              left: 10,
              top: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _scannerController,
                  builder: (context, state, child) {
                    switch (state.torchState) {
                      case TorchState.off:
                        return IconButton(
                          icon: const Icon(Icons.flash_off, color: Colors.white),
                          onPressed: () => _scannerController.toggleTorch(),
                        );
                      case TorchState.on:
                        return IconButton(
                          icon: const Icon(Icons.flash_on, color: Colors.yellow),
                          onPressed: () => _scannerController.toggleTorch(),
                        );
                      default:
                        return const SizedBox.shrink();
                    }
                  },
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _isScanningSku = false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkuField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _skuController,
            style: const TextStyle(color: Colors.white),
            maxLength: 16,
            onChanged: (val) {
              if (_skuExistenteNombre != null) {
                setState(() => _skuExistenteNombre = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'SKU (Máx 16) *',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              counterText: '',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isCheckingSku)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      _isScanningSku ? Icons.close : Icons.qr_code_scanner,
                      color: _isScanningSku ? Colors.redAccent : Colors.blueAccent,
                    ),
                    tooltip: _isScanningSku ? 'Cerrar escáner' : 'Escanear SKU con cámara',
                    onPressed: () {
                      setState(() => _isScanningSku = !_isScanningSku);
                    },
                  ),
                ],
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Este campo es obligatorio';
              }
              if (_skuExistenteNombre != null) {
                return 'SKU ya registrado para: $_skuExistenteNombre';
              }
              return null;
            },
          ),
          if (_skuExistenteNombre != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'SKU en uso por: $_skuExistenteNombre',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {bool isRequired = false, bool isNumeric = false, int maxLength = 255}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        maxLength: maxLength < 255 ? maxLength : null,
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          counterText: '',
        ),
        validator: isRequired
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Este campo es obligatorio';
                }
                return null;
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Crear Producto'),
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (_isScanningSku) _buildScannerBox(),
                    _buildSkuField(),
                    _buildField('Descripción Principal', _descripcion1Controller, isRequired: true),
                    
                    const Divider(color: Colors.white24, height: 40),
                    
                    Row(
                      children: [
                        Expanded(child: _buildField('Costo', _costoController, isNumeric: true)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildField('Precio de Venta', _precioVentaController, isNumeric: true)),
                      ],
                    ),
                    
                    const Divider(color: Colors.white24, height: 40),
                    
                    Row(
                      children: [
                        Expanded(child: _buildField('UPC', _upcController)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildField('ALU', _aluController)),
                      ],
                    ),
                    
                    Row(
                      children: [
                        Expanded(child: _buildField('Marca', _marcaController)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildField('Color', _colorController)),
                      ],
                    ),

                    Row(
                      children: [
                        Expanded(child: _buildField('Categoría', _categoriaController)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildField('Clase', _claseController)),
                      ],
                    ),
                    
                    Row(
                      children: [
                        Expanded(child: _buildField('Sub-clase', _subClaseController)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildField('Estilo', _estiloController)),
                      ],
                    ),

                    _buildField('Descripción Secundaria', _descripcion2Controller),
                    
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                        onPressed: _guardarProducto,
                        child: const Text('GUARDAR PRODUCTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}
