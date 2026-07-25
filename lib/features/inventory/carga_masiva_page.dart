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

        // Obtener headers limpios (lowercase + trim)
        List<String> headers = csvTable.first
            .map((e) => e.toString().trim().toLowerCase())
            .toList();

        // ── Tabla de alias: nombres alternativos → nombre canónico ──────────
        // Permite importar el CSV exportado por la app sin renombrar columnas.
        const Map<String, String> _alias = {
          // Tienda
          'tienda'         : 'codigo_tienda',
          // Precio
          'precio'         : 'precio_venta',
          'precio venta'   : 'precio_venta',
          'precio_venta'   : 'precio_venta',
          // Descripción 1
          'descripcion'    : 'descripcion_1',
          'descripción'    : 'descripcion_1',
          'description'    : 'descripcion_1',
          // Descripción 2
          'descripcion 2'  : 'descripcion_2',
          'descripcion_2'  : 'descripcion_2',
          'descripción 2'  : 'descripcion_2',
          // Sub-clase
          'subclase'       : 'sub_clase',
          'sub clase'      : 'sub_clase',
          // Marca / Estilo / Color sin cambio pero cubiertas por si acaso
        };

        // Normalizar headers aplicando alias
        headers = headers.map((h) => _alias[h] ?? h).toList();

        // Headers obligatorios requeridos
        final requiredHeaders = ['sku', 'codigo_tienda', 'precio_venta', 'costo'];
        for (var req in requiredHeaders) {
          if (!headers.contains(req)) {
            _mostrarError(
              "Falta la columna obligatoria: '$req'.\n"
              "Columnas recibidas: ${headers.join(', ')}",
            );
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
          final String sku = rowMap['sku']?.toString().trim() ?? '';
          final String codigoTienda = rowMap['codigo_tienda']?.toString().trim() ?? '';
          final num precioVenta = num.tryParse(rowMap['precio_venta']?.toString() ?? '') ?? 0;
          final num costo = num.tryParse(rowMap['costo']?.toString() ?? '') ?? 0;

          if (sku.isEmpty || codigoTienda.isEmpty) continue;
          
          if (precioVenta <= costo) {
            // Se descarta silenciosamente para la BD.
            continue; 
          }

          // Extraer, sanitizar y mapear explícitamente campos opcionales
          final String? valorExtraidoAlu = rowMap['alu']?.toString().trim();
          final String? valorExtraidoDesc1 = rowMap['descripcion_1']?.toString().trim();
          final String? valorExtraidoDesc2 = rowMap['descripcion_2']?.toString().trim();

          if (valorExtraidoDesc1 != null && valorExtraidoDesc1.isNotEmpty) {
            rowMap['descripcion_1'] = valorExtraidoDesc1;
          }
          rowMap['alu'] = (valorExtraidoAlu != null && valorExtraidoAlu.isNotEmpty) ? valorExtraidoAlu : null;
          rowMap['descripcion_2'] = (valorExtraidoDesc2 != null && valorExtraidoDesc2.isNotEmpty) ? valorExtraidoDesc2 : null;

          payload.add(rowMap);
          if (preview.length <= 5) preview.add(row);
        }

        if (payload.isEmpty) {
          _mostrarError("No se encontraron filas válidas.\n• Verifica que el precio sea mayor al costo.\n• Verifica que SKU y Tienda no estén vacíos.");
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

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent),
                SizedBox(width: 10),
                Text("🚀 Carga Exitosa", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              response.toString(),
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                onPressed: () {
                  Navigator.pop(ctx);
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text("VOLVER AL INVENTARIO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
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
                    Text("• Títulos Opcionales:\n   [upc, alu, descripcion_1, descripcion_2, stock]", style: TextStyle(color: Colors.white70)),
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
