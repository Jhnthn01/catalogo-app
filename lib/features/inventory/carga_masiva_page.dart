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
        List<String> rawHeaders = csvTable.first
            .map((e) => e.toString().trim().toLowerCase())
            .toList();

        // ── Tabla de alias: nombres alternativos → nombre canónico ──────────
        // Permite importar el CSV exportado por la app sin renombrar columnas.
        const Map<String, String> alias = {
          // Tienda
          'tienda'                   : 'codigo_tienda',
          'tienda_id'                : 'codigo_tienda',
          // Precio
          'precio'                   : 'precio_venta',
          'precio venta'             : 'precio_venta',
          'precio_venta'             : 'precio_venta',
          // Descripción 1
          'descripcion'              : 'descripcion_1',
          'descripción'              : 'descripcion_1',
          'description'              : 'descripcion_1',
          'descripcion_1'            : 'descripcion_1',
          // Descripción 2 — la columna 'clase' en tu CSV exportado es en realidad sub_clase
          'descripcion 2'            : 'descripcion_2',
          'descripcion_2'            : 'descripcion_2',
          'descripción 2'            : 'descripcion_2',
          // Sub-clase (el CSV exportado tiene 'clase' en posición 5 como sub_clase)
          'subclase'                 : 'sub_clase',
          'sub clase'                : 'sub_clase',
          'sub_clase'                : 'sub_clase',
          // Categoría
          'categoria'                : 'categoria',
          'categoría'                : 'categoria',
          // Estilo
          'estilo'                   : 'estilo',
          // Marca
          'marca'                    : 'marca',
          // Color
          'color'                    : 'color',
          // Stock
          'stock'                    : 'stock',
          // Costo
          'costo'                    : 'costo',
        };

        // Normalizar headers aplicando alias
        List<String> headers = rawHeaders.map((h) => alias[h] ?? h).toList();

        // ── Manejar columnas duplicadas: si hay dos 'descripcion_2',
        //    la PRIMERA que aparezca en el CSV como 'clase' viene del exportador
        //    como sub_clase. Renombrar duplicados correctamente.
        final Map<String, int> seenCount = {};
        for (int i = 0; i < headers.length; i++) {
          final h = headers[i];
          seenCount[h] = (seenCount[h] ?? 0) + 1;
          if (seenCount[h]! > 1) {
            // Segunda aparición de un header duplicado — se descarta asignando sufijo _dup
            headers[i] = '${h}_dup${seenCount[h]}';
          }
        }

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

        // Helper para sanitizar entradas numéricas (elimina comas de miles '1,500.00' -> '1500.00')
        double parseCleanDouble(dynamic rawVal) {
          if (rawVal == null) return 0.0;
          String s = rawVal.toString().trim();
          if (s.isEmpty) return 0.0;
          s = s.replaceAll('S/.', '').replaceAll(r'$', '').replaceAll(' ', '');
          if (s.contains(',') && s.contains('.')) {
            s = s.replaceAll(',', '');
          } else if (s.contains(',') && !s.contains('.')) {
            if (RegExp(r',\d{1,2}$').hasMatch(s)) {
              s = s.replaceAll(',', '.');
            } else {
              s = s.replaceAll(',', '');
            }
          }
          return double.tryParse(s) ?? 0.0;
        }

        // Procesar Filas (Empezando desde la fila 1)
        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;

          Map<String, dynamic> rowMap = {};
          for (int j = 0; j < headers.length && j < row.length; j++) {
            rowMap[headers[j]] = row[j];
          }

          // Validar lógicamente las reglas de negocio base
          final String sku = rowMap['sku']?.toString().trim() ?? '';
          final String codigoTienda = rowMap['codigo_tienda']?.toString().trim() ?? '';
          final double precioVenta = parseCleanDouble(rowMap['precio_venta']);
          final double costo = parseCleanDouble(rowMap['costo']);

          if (sku.isEmpty || codigoTienda.isEmpty) continue;

          // Solo descartar si el precio es estrictamente menor al costo (no igual)
          if (precioVenta > 0 && costo > 0 && precioVenta < costo) continue;

          // Asignar valores numéricos sanitizados
          rowMap['precio_venta'] = precioVenta;
          rowMap['costo'] = costo;
          if (rowMap['stock'] != null) {
            rowMap['stock'] = parseCleanDouble(rowMap['stock']).round();
          }
          if (rowMap['ultimo_costo'] != null) {
            rowMap['ultimo_costo'] = parseCleanDouble(rowMap['ultimo_costo']);
          }
          if (rowMap['costo_medio'] != null) {
            rowMap['costo_medio'] = parseCleanDouble(rowMap['costo_medio']);
          }

          // Extraer y sanitizar campos opcionales de texto
          final String? valorAlu = rowMap['alu']?.toString().trim();
          final String? valorDesc1 = rowMap['descripcion_1']?.toString().trim();
          final String? valorDesc2 = rowMap['descripcion_2']?.toString().trim();

          if (valorDesc1 != null && valorDesc1.isNotEmpty) {
            rowMap['descripcion_1'] = valorDesc1;
          }
          rowMap['alu'] = (valorAlu != null && valorAlu.isNotEmpty) ? valorAlu : null;
          rowMap['descripcion_2'] = (valorDesc2 != null && valorDesc2.isNotEmpty) ? valorDesc2 : null;

          // Eliminar columnas duplicadas o irrelevantes para Supabase
          rowMap.remove('descripcion_2_dup2');
          rowMap.remove('descripcion_2_dup3');

          payload.add(rowMap);
          if (preview.length <= 6) preview.add(row);
        }

        if (payload.isEmpty) {
          _mostrarError("No se encontraron filas válidas.\n• Verifica que el SKU y Tienda no estén vacíos.\n• Columnas detectadas: ${headers.join(', ')}");
          return;
        }

        setState(() {
          _previewData = preview;
          _payloadListo = payload;
          _statusMessage = "¡Archivo leído! ${payload.length} filas válidas de ${csvTable.length - 1} totales.";
        });
      }
    } catch (e) {
      _mostrarError("Error leyendo CSV: $e");
    }
  }

  Future<void> _subirBaseDeDatos() async {
    if (_payloadListo.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    // Capturar el count antes de limpiar el payload
    final int totalFilas = _payloadListo.length;

    try {
      final response = await _supabase.rpc('process_bulk_upload', params: {
        'payload': _payloadListo
      });

      if (!mounted) return;

      // La función SQL puede devolver null si no tiene RETURN explícito; 
      // en ese caso asumimos éxito porque no hubo excepción.
      final String mensajeRespuesta = (response != null && response.toString().isNotEmpty && response.toString() != 'null')
          ? response.toString()
          : '✅ $totalFilas productos procesados correctamente.';

      setState(() {
        _isLoading = false;
        _statusMessage = mensajeRespuesta;
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
            mensajeRespuesta,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("VOLVER AL INVENTARIO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      // Después de cerrar el diálogo, regresar a la pantalla anterior con resultado true
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
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
