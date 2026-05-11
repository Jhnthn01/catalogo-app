import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NuevoProductoPage extends StatefulWidget {
  const NuevoProductoPage({super.key});

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

  bool _isLoading = false;

  @override
  void dispose() {
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

  Future<void> _guardarProducto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final double costo = double.tryParse(_costoController.text) ?? 0.0;
      final double precio = double.tryParse(_precioVentaController.text) ?? 0.0;

      await Supabase.instance.client.from('productos').insert({
        'sku': _skuController.text.trim(),
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
          counterText: '', // Ocultar contador de caracteres si no es necesario
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
                    _buildField('SKU (Máx 16)', _skuController, isRequired: true, maxLength: 16),
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
