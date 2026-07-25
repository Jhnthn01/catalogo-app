import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Servicio de actualizaciones automáticas para Android y Windows.
///
/// Android → Abre la URL del APK en el navegador. El SO detecta el APK
///            descargado y ofrece instalarlo (sin necesidad de Play Store).
/// Windows → Abre el enlace del instalador/ZIP en el navegador o explorador.
class UpdateService {
  static bool _dialogoAbierto = false;

  /// Verifica si hay una nueva versión disponible consultando `app_versiones` en Supabase.
  /// [silencioso] = true  → sólo muestra el diálogo si hay actualización.
  /// [silencioso] = false → muestra snackbar "estás al día" si no hay nada.
  static Future<void> verificarActualizacion(
    BuildContext context, {
    bool silencioso = true,
  }) async {
    if (kIsWeb || _dialogoAbierto) return;
    if (!Platform.isAndroid && !Platform.isWindows) return;

    final String plataforma = Platform.isAndroid ? 'android' : 'windows';

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final int currentBuildNumber =
          int.tryParse(packageInfo.buildNumber) ?? 1;

      final data = await Supabase.instance.client
          .from('app_versiones')
          .select()
          .eq('plataforma', plataforma)
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        if (!silencioso && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tu aplicación ya está actualizada.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      final int remoteVersionCode =
          (data['version_code'] as num?)?.toInt() ?? 0;
      final String versionStr = data['version'] ?? 'Nueva versión';
      final String urlDescarga = data['url_descarga'] ?? '';
      final String notas =
          data['notas'] ?? 'Mejoras y correcciones en la aplicación.';
      final bool obligatoria = data['obligatoria'] ?? false;

      if (remoteVersionCode > currentBuildNumber && urlDescarga.isNotEmpty) {
        if (!context.mounted) return;
        _dialogoAbierto = true;
        await showDialog(
          context: context,
          barrierDismissible: !obligatoria,
          builder: (_) => _DialogoActualizacion(
            plataforma: plataforma,
            versionStr: versionStr,
            urlDescarga: urlDescarga,
            notas: notas,
            obligatoria: obligatoria,
          ),
        );
        _dialogoAbierto = false;
      } else if (!silencioso && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tu app (v${packageInfo.version}+${packageInfo.buildNumber}) está al día.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('UpdateService error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _DialogoActualizacion extends StatefulWidget {
  final String plataforma;
  final String versionStr;
  final String urlDescarga;
  final String notas;
  final bool obligatoria;

  const _DialogoActualizacion({
    required this.plataforma,
    required this.versionStr,
    required this.urlDescarga,
    required this.notas,
    required this.obligatoria,
  });

  @override
  State<_DialogoActualizacion> createState() => _DialogoActualizacionState();
}

class _DialogoActualizacionState extends State<_DialogoActualizacion> {
  bool _abriendo = false;
  String _errorMensaje = '';

  Future<void> _abrirDescarga() async {
    setState(() {
      _abriendo = true;
      _errorMensaje = '';
    });

    final uri = Uri.parse(widget.urlDescarga);
    try {
      final bool lanzado = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!lanzado && mounted) {
        setState(() {
          _abriendo = false;
          _errorMensaje = 'No se pudo abrir el enlace de descarga.';
        });
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _abriendo = false;
          _errorMensaje = 'Error: $e';
        });
        return;
      }
    }

    // Cerrar el diálogo después de lanzar la descarga
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool esAndroid = widget.plataforma == 'android';

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.obligatoria
                ? Icons.system_update_alt
                : Icons.system_update,
            color:
                widget.obligatoria ? Colors.orangeAccent : Colors.tealAccent,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.obligatoria
                  ? 'Actualización Obligatoria'
                  : 'Nueva Versión Disponible',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  esAndroid ? Icons.android : Icons.desktop_windows,
                  color: Colors.white54,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Versión v${widget.versionStr} '
                    '(${widget.plataforma.toUpperCase()})',
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Novedades:',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                widget.notas,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
            if (esAndroid) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Text(
                  '💡 Se abrirá el navegador para descargar el APK. '
                  'Una vez descargado, toca el archivo para instalarlo.',
                  style: TextStyle(color: Colors.orange, fontSize: 11),
                ),
              ),
            ],
            if (_errorMensaje.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _errorMensaje,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.obligatoria && !_abriendo)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Más Tarde',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent,
            disabledBackgroundColor: Colors.tealAccent.withOpacity(0.4),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _abriendo ? null : _abrirDescarga,
          icon: _abriendo
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black54),
                )
              : Icon(
                  esAndroid
                      ? Icons.download_for_offline
                      : Icons.open_in_browser,
                  color: Colors.black,
                  size: 18,
                ),
          label: Text(
            _abriendo
                ? 'Abriendo...'
                : esAndroid
                    ? 'DESCARGAR APK'
                    : 'DESCARGAR INSTALADOR',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
