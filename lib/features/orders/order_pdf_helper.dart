import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
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
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "EBORJA S.A.C.",
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          "VENTA DE ARTÍCULOS DE FERRETERÍA EN GENERAL / PANELES SOLARES, ACCESORIOS Y BATERÍAS / LUBRICANTES, FILTROS, LLANTAS Y REPUESTOS EN GENERAL",
                          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "PEDIDOS AL POR MAYOR Y MENOR / ATENDEMOS PEDIDOS A PROVINCIA",
                          style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          "Sucursales:\n Mz. 12 Lt. 25 Av. Andrés A. Cáceres - Los Rosales - Pampa - Lima Sur\n Los Girasoles - Av. Manuel Valdivia Valle Mz. E2 Lt. 01",
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "Telfs: 933 588 215 / 908 873 890",
                          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 15),
                  pw.Container(
                    width: 150,
                    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blue900, width: 2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          "R.U.C. Nº 20600593634",
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          pedido['tipo_comprobante']?.toString().toUpperCase() ?? "PROFORMA",
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          "Nº #$idCorto",
                          style: pw.TextStyle(
                            fontSize: 12,
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
                  0: pw.FlexColumnWidth(1),     // CANT.
                  1: pw.FlexColumnWidth(4.5),   // DESCRIPCION
                  2: pw.FlexColumnWidth(1.2),   // P. UNIT.
                  3: pw.FlexColumnWidth(1.3),   // IMPORTE
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue900),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("CANT.", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("DESCRIPCION", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("P. UNIT.", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("IMPORTE", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  ...items.map((item) {
                    final double subtotal = item.precio * item.cantidad;
                    final String cantFormateada = item.cantidad.toString().padLeft(2, '0');
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(cantFormateada, style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(item.nombre.toUpperCase(), style: pw.TextStyle(fontSize: 9)),
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
                  "Gracias por su preferencia - EBORJA S.A.C.",
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
                      "EBORJA S.A.C.",
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      "VENTA DE ARTÍCULOS DE FERRETERÍA EN GENERAL\nPANELES SOLARES, ACCESORIOS Y BATERÍAS\nLUBRICANTES, FILTROS, LLANTAS Y REPUESTOS",
                      style: const pw.TextStyle(fontSize: 6),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      "PEDIDOS AL POR MAYOR Y MENOR\nATENDEMOS PEDIDOS A PROVINCIA",
                      style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text("R.U.C. Nº 20600593634", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                    pw.Text("Sucursales:\n• Mz. 12 Lt. 25 Av. Andrés A. Cáceres - Los Rosales - Pampa\n• Los Girasoles - Av. Manuel Valdivia Valle", style: pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.center),
                    pw.Text("Telfs: 933 588 215 / 908 873 890", style: pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 6),
                    pw.Text("--------------------------------", style: pw.TextStyle(fontSize: 9)),
                    pw.Text(
                      pedido['tipo_comprobante']?.toString().toUpperCase() ?? "PROFORMA",
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text("ID: #$idCorto", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
              pw.Table(
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.8), // CANT.
                  1: pw.FlexColumnWidth(2.8), // DESCRIPCION
                  2: pw.FlexColumnWidth(1.1), // P. UNIT.
                  3: pw.FlexColumnWidth(1.3), // IMPORTE
                },
                children: [
                  pw.TableRow(
                    children: [
                      pw.Text("CANT", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      pw.Text("DESCRIPCION", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      pw.Text("P.UNIT", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                      pw.Text("IMPORTE", style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Text("----", style: pw.TextStyle(fontSize: 6)),
                      pw.Text("--------------------", style: pw.TextStyle(fontSize: 6)),
                      pw.Text("-------", style: pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.right),
                      pw.Text("---------", style: pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.right),
                    ],
                  ),
                  ...items.map((item) {
                    final double subtotal = item.precio * item.cantidad;
                    final String cantFormateada = item.cantidad.toString().padLeft(2, '0');
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                          child: pw.Text(cantFormateada, style: pw.TextStyle(fontSize: 7)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                          child: pw.Text(item.nombre.toUpperCase(), style: pw.TextStyle(fontSize: 7)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                          child: pw.Text(item.precio.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                          child: pw.Text(subtotal.toStringAsFixed(2), style: pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 6),
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

  static Future<void> enviarWhatsApp(BuildContext context, Map<String, dynamic> pedido) async {
    final String? telefonoRaw = pedido['telefono_cliente']?.toString();
    if (telefonoRaw == null || telefonoRaw.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("El cliente no tiene un número de teléfono registrado."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    String cleanPhone = telefonoRaw.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Número de teléfono inválido."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (cleanPhone.length == 9) {
      cleanPhone = '51$cleanPhone';
    }

    final double totalNeto = pedido['total_despachado'] != null
        ? double.parse(pedido['total_despachado'].toString())
        : (pedido['total'] != null ? double.parse(pedido['total'].toString()) : 0.0);

    final String idCorto = pedido['id'].toString().substring(0, 8).toUpperCase();
    final String nombreCliente = pedido['nombre_cliente'] ?? 'cliente';

    final String mensaje = "Estimado(a) $nombreCliente, adjuntamos la información de su pedido número $idCorto por un total de S/. ${totalNeto.toStringAsFixed(2)}. ¡Gracias por su preferencia!";
    
    final String urlString = "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(mensaje)}";
    final Uri url = Uri.parse(urlString);

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw 'No se pudo abrir WhatsApp.';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al abrir WhatsApp: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
