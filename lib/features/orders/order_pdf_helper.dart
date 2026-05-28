import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:catalogo_digital_app/services/cart_service.dart';

class OrderPdfHelper {
  static Future<Uint8List> generateA4({
    required Map<String, dynamic> pedido,
    required List<CartItem> items,
  }) async {
    final pdf = pw.Document();

    final DateTime fechaCreacion = pedido['creado_en'] != null 
        ? DateTime.parse(pedido['creado_en']).toLocal() 
        : DateTime.now();
    final DateTime? fechaEntrega = pedido['fecha_entrega'] != null 
        ? DateTime.parse(pedido['fecha_entrega']).toLocal() 
        : null;

    final String idCorto = pedido['id'].toString().substring(0, 8).toUpperCase();
    
    final double totalNeto = pedido['total_despachado'] != null
        ? double.parse(pedido['total_despachado'].toString())
        : (pedido['total'] != null ? double.parse(pedido['total'].toString()) : 0.0);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Cabecera Corporativa
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "FERRETERÍA PRO LIMA S.A.C.",
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text("RUC: 20765432109", style: pw.TextStyle(fontSize: 10)),
                      pw.Text("Av. La Marina 1542, San Miguel, Lima", style: pw.TextStyle(fontSize: 9)),
                      pw.Text("Telf: (01) 456-7890 | ventas@ferreteriapro.pe", style: pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blue900, width: 2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          pedido['tipo_comprobante']?.toString().toUpperCase() ?? "COMPROBANTE",
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          "Nº #$idCorto",
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 10),

              // Datos del Cliente y Envío
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "DATOS DEL CLIENTE",
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text("Cliente: ${pedido['nombre_cliente'] ?? 'No especificado'}", style: pw.TextStyle(fontSize: 10)),
                        pw.Text("Doc: ${pedido['tipo_documento'] ?? 'DNI'} ${pedido['numero_documento'] ?? ''}", style: pw.TextStyle(fontSize: 10)),
                        pw.Text("Dirección: ${pedido['direccion_cliente'] ?? 'No especificada'}", style: pw.TextStyle(fontSize: 10)),
                        pw.Text("Teléfono: ${pedido['telefono_cliente'] ?? 'No especificado'}", style: pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "DETALLES DE ENTREGA / PAGO",
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text("Fecha Pedido: ${DateFormat('dd/MM/yyyy hh:mm a').format(fechaCreacion)}", style: pw.TextStyle(fontSize: 10)),
                        if (fechaEntrega != null)
                          pw.Text("Fecha Entrega: ${DateFormat('dd/MM/yyyy hh:mm a').format(fechaEntrega)}", style: pw.TextStyle(fontSize: 10, color: PdfColors.blue900)),
                        pw.Text("Forma de Pago: ${pedido['forma_pago'] ?? 'Efectivo'}", style: pw.TextStyle(fontSize: 10)),
                        if (pedido['segundo_recoge'] != null && pedido['segundo_recoge'].toString().isNotEmpty)
                          pw.Text("Autorizado a recoger: ${pedido['segundo_recoge']}", style: pw.TextStyle(fontSize: 10)),
                        if (pedido['entregado_a'] != null && pedido['entregado_a'].toString().isNotEmpty)
                          pw.Text("Entregado a: ${pedido['entregado_a']}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Tabla de productos
              pw.Text(
                "DETALLE DE PRODUCTOS",
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(width: 0.5, color: PdfColors.grey300),
                  bottom: pw.BorderSide(width: 1, color: PdfColors.grey400),
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(1.2),
                  3: pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue900),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("Descripción", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("Cant.", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("P. Unitario", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("Importe", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  ...items.map((item) {
                    final double subtotal = item.precio * item.cantidad;
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(item.nombre, style: pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(item.cantidad.toString(), style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text("S/.${item.precio.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text("S/.${subtotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 15),

              // Total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text(
                            pedido['estado']?.toString().toLowerCase() == 'entregado'
                                ? "TOTAL NETO COBRADO:  "
                                : "TOTAL GENERAL:  ",
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                          pw.Text(
                            "S/.${totalNeto.toStringAsFixed(2)}",
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              pw.Spacer(),

              // Pie de página
              pw.Center(
                child: pw.Text(
                  "Gracias por su preferencia - FERRETERÍA PRO LIMA",
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> generateTicket({
    required Map<String, dynamic> pedido,
    required List<CartItem> items,
  }) async {
    final pdf = pw.Document();

    final DateTime fechaCreacion = pedido['creado_en'] != null 
        ? DateTime.parse(pedido['creado_en']).toLocal() 
        : DateTime.now();
    final DateTime? fechaEntrega = pedido['fecha_entrega'] != null 
        ? DateTime.parse(pedido['fecha_entrega']).toLocal() 
        : null;

    final String idCorto = pedido['id'].toString().substring(0, 8).toUpperCase();
    
    final double totalNeto = pedido['total_despachado'] != null
        ? double.parse(pedido['total_despachado'].toString())
        : (pedido['total'] != null ? double.parse(pedido['total'].toString()) : 0.0);

    // Custom layout optimized for 80mm roll printer
    final pdfTheme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoMonoRegular(),
      bold: await PdfGoogleFonts.robotoMonoBold(),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 6 * PdfPageFormat.mm,
        ),
        theme: pdfTheme,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Centro de ticket
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      "FERRETERÍA PRO LIMA",
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text("Av. La Marina 1542, San Miguel", style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
                    pw.Text("RUC: 20765432109", style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 6),
                    pw.Text("--------------------------------", style: pw.TextStyle(fontSize: 9)),
                    pw.Text(
                      pedido['tipo_comprobante']?.toString().toUpperCase() ?? "TICKET DE PEDIDO",
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text("ID: #$idCorto", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text("--------------------------------", style: pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),

              // Datos Básicos
              pw.Text("Cliente: ${pedido['nombre_cliente'] ?? 'No especificado'}", style: pw.TextStyle(fontSize: 8)),
              pw.Text("Direcc: ${pedido['direccion_cliente'] ?? 'No especificada'}", style: pw.TextStyle(fontSize: 8)),
              pw.Text("Telf: ${pedido['telefono_cliente'] ?? ''}", style: pw.TextStyle(fontSize: 8)),
              pw.Text("Fecha: ${DateFormat('dd/MM/yyyy hh:mm a').format(fechaCreacion)}", style: pw.TextStyle(fontSize: 8)),
              if (fechaEntrega != null)
                pw.Text("Entrega: ${DateFormat('dd/MM/yyyy hh:mm a').format(fechaEntrega)}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text("Pago: ${pedido['forma_pago'] ?? ''}", style: pw.TextStyle(fontSize: 8)),
              if (pedido['segundo_recoge'] != null && pedido['segundo_recoge'].toString().isNotEmpty)
                pw.Text("Recoge: ${pedido['segundo_recoge']}", style: pw.TextStyle(fontSize: 8)),
              if (pedido['entregado_a'] != null && pedido['entregado_a'].toString().isNotEmpty)
                pw.Text("Entregado a: ${pedido['entregado_a']}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              
              pw.SizedBox(height: 6),
              pw.Text("--------------------------------", style: pw.TextStyle(fontSize: 9)),
              pw.Text("CANT  DESCRIPCIÓN      IMPORTE", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text("--------------------------------", style: pw.TextStyle(fontSize: 9)),
              
              // Items
              ...items.map((item) {
                final double subtotal = item.precio * item.cantidad;
                // Format description to be compact
                final String desc = item.nombre.length > 18 
                    ? "${item.nombre.substring(0, 16)}.." 
                    : item.nombre;
                
                final String qtyStr = item.cantidad.toString().padRight(4);
                final String descStr = desc.padRight(18);
                final String totalStr = "S/.${subtotal.toStringAsFixed(2)}".padLeft(8);

                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Text("$qtyStr$descStr$totalStr", style: pw.TextStyle(fontSize: 8)),
                );
              }),

              pw.Text("--------------------------------", style: pw.TextStyle(fontSize: 9)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    pedido['estado']?.toString().toLowerCase() == 'entregado'
                        ? "NETO COBRADO:"
                        : "TOTAL A PAGAR:",
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    "S/.${totalNeto.toStringAsFixed(2)}",
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Text("--------------------------------", style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text("¡GRACIAS POR SU COMPRA!", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                    pw.Text("Mencione su nombre en caja", style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
