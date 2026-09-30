import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:catalogo_digital_app/services/toma_inventario_service.dart';
import 'package:catalogo_digital_app/features/inventory/conteo_toma_page.dart';

class TomaProgresoCard extends StatelessWidget {
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onRetomado;

  const TomaProgresoCard({
    super.key,
    this.margin,
    this.onRetomado,
  });

  String _formatearTiempoTranscurrido(DateTime inicio) {
    final diff = DateTime.now().difference(inicio);
    if (diff.inMinutes < 1) return 'Iniciada hace un momento';
    if (diff.inMinutes < 60) return 'Iniciada hace ${diff.inMinutes} min';
    final horas = diff.inHours;
    final mins = diff.inMinutes % 60;
    return 'Iniciada hace ${horas}h ${mins}m';
  }

  void _confirmarDescartar(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '¿Descartar Toma de Inventario?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Se removerá la sesión de la memoria. Si deseas registrar los ajustes formalmente, usa el botón "Cerrar Conteo" dentro de la toma.\n\n¿Deseas descartar este progreso local?',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Volver', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              TomaInventarioService().cancelarSesion();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sesión de toma descartada de la memoria.'),
                  backgroundColor: Colors.orangeAccent,
                ),
              );
            },
            child: const Text('Sí, Descartar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TomaActivaSesion?>(
      valueListenable: TomaInventarioService().sesionActiva,
      builder: (context, sesion, child) {
        if (sesion == null) {
          return const SizedBox.shrink();
        }

        final horaInicio = DateFormat('hh:mm a').format(sesion.fechaInicio.toLocal());
        final tiempoTexto = _formatearTiempoTranscurrido(sesion.fechaInicio);

        return Container(
          margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF142C2A), Color(0xFF1A1F2C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabecera: Badge en progreso y botón descartar ────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radio_button_checked, color: Colors.tealAccent, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'TOMA EN PROGRESO',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                      tooltip: 'Descartar progreso de memoria',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _confirmarDescartar(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Datos de la Toma ─────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.checklist_rtl_rounded, color: Colors.tealAccent, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sesion.tiendaNombre,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sesion.alcanceTexto,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$tiempoTexto ($horaInicio)',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Barra de Progreso / Conteo y Botón Retomar ─────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10171D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, color: Colors.tealAccent, size: 20),
                          const SizedBox(width: 8),
                          RichText(
                            text: TextSpan(
                              text: '${sesion.totalContados} ',
                              style: const TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              children: const [
                                TextSpan(
                                  text: 'productos contados',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text(
                          'RETOMAR',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                        ),
                        onPressed: () {
                          if (onRetomado != null) onRetomado!();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ConteoTomaPage(tomaId: sesion.tomaId),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
