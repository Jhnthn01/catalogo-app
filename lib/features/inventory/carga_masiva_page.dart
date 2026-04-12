import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CargaMasivaPage extends StatefulWidget {
  const CargaMasivaPage({super.key});

  @override
  State<CargaMasivaPage> createState() => _CargaMasivaPageState();
}

class _CargaMasivaPageState extends State<CargaMasivaPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String _statusMessage = "Adjunta tu archivo .csv validado para comenzar.";
  List<List<dynamic>> _previewData = [];
  List<Map<String, dynamic>> _payloadListo = [];

  Future<void> _seleccionarArchivo() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final csvString = utf8.decode(bytes);
        
        List<List<dynamic>> csvTable = csv.decode(csvString);
        
        if (csvTable.isEmpty) {
          _mostrarError("El archivo está vacío.");
          return;
        }

        // Obtener headers limpios
        final headers = csvTable.first.map((e) => e.toString().trim().toLowerCase()).toList();
        
        // Headers obligatorios requeridos
        final requiredHeaders = ['sku', 'codigo_tienda', 'precio_venta', 'costo'];
        for (var req in requiredHeaders) {
          if (!headers.contains(req)) {
            _mostrarError("Falta la columna obligatoria: $req");
            return;
          }
        }

        List<Map<String, dynamic>> payload = [];
        List<List<dynamic>> preview = [headers];

        // Procesar Filas (Empezando desde la fila 1)
        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.isEmpty || row.length < headers.length) continue; // Saltar filas deformes

          Map<String, dynamic> rowMap = {};
          for (int j = 0; j < headers.length; j++) {
            rowMap[headers[j]] = row[j];
          }

          // Validar lógicamente las reglas de negocio base
          final String sku = rowMap['sku']?.toString() ?? '';
          final String codigoTienda = rowMap['codigo_tienda']?.toString() ?? '';
          final num precioVenta = num.tryParse(rowMap['precio_venta'].toString()) ?? 0;
          final num costo = num.tryParse(rowMap['costo'].toString()) ?? 0;

          if (sku.isEmpty || codigoTienda.isEmpty) continue;
          
          if (precioVenta <= costo) {
            // Se descarta silenciosamente para la BD, o podriamos informar.
            continue; 
          }

          payload.add(rowMap);
          if (preview.length <= 5) preview.add(row);
        }

        if (payload.isEmpty) {
          _mostrarError("No se encontraron filas que cumplan las validaciones (Mismo precio que costo, o vacías).");
          return;
        }

        setState(() {
          _previewData = preview;
          _payloadListo = payload;
          _statusMessage = "¡Archivo leído! ${payload.length} filas válidas encontradas y listas para procesarse.";
        });
      }
    } catch (e) {
      _mostrarError("Error leyendo CSV: $e");
    }
  }

  Future<void> _subirBaseDeDatos() async {
    if (_payloadListo.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final response = await _supabase.rpc('process_bulk_upload', params: {
        'payload': _payloadListo
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = response.toString();
          _previewData = [];
          _payloadListo = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🚀 ¡Carga completada con éxito!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _mostrarError("Error procesando carga: $e\n(¿Olvidaste correr el Script SQL en Supabase?)");
      }
    }
  }

  void _mostrarError(String msg) {
    setState(() => _statusMessage = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Carga Masiva (CSV)"),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.blue.shade800),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Reglas del Documento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 8),
                    Text("• Formato obligatorio: .CSV delimitado por comas.", style: TextStyle(color: Colors.white70)),
                    Text("• Títulos de Mínimos Requeridos:\n   [sku, codigo_tienda, precio_venta, costo]", style: TextStyle(color: Colors.blueAccent)),
                    Text("• Títulos Opcionales:\n   [upc, alu, descripcion_1, stock]", style: TextStyle(color: Colors.white70)),
                    Text("• Las filas con precio de venta menor o igual al costo serán descartadas automáticamente.", style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _seleccionarArchivo,
                icon: const Icon(Icons.upload_file),
                label: const Text("Adjuntar Archivo CSV"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF1E1E1E),
                  side: const BorderSide(color: Colors.blueAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                ),
              ),
              const SizedBox(height: 20),
              
              Text(
                _statusMessage, 
                style: TextStyle(
                  color: _statusMessage.contains("Error") ? Colors.redAccent : Colors.greenAccent, 
                  fontWeight: FontWeight.bold
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              if (_previewData.isNotEmpty) ...[
                const Text("Vista Previa (Primeras 5 filas):", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.blue.withOpacity(0.2)),
                    columns: _previewData.first.map((e) => DataColumn(label: Text(e.toString(), style: const TextStyle(color: Colors.white)))).toList(),
                    rows: _previewData.skip(1).map((row) {
                      return DataRow(
                        cells: row.map((e) => DataCell(Text(e.toString(), style: const TextStyle(color: Colors.white70)))).toList(),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 30),
                
                if (_isLoading)
                   const Center(child: CircularProgressIndicator())
                else
                  ElevatedButton(
                    onPressed: _subirBaseDeDatos,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                    child: const Text("PROCESAR Y CARGAR A BASE DE DATOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
              ]
            ],
          ),
        ),
      ),
    );
  }
}
