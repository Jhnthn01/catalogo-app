import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

class TomaActivaSesion {
  final String tomaId;
  final int? tiendaId;
  final String tiendaNombre;
  final String alcanceTexto;
  final DateTime fechaInicio;
  int totalContados;
  final String? categoria;
  final String? clase;
  final String? subClase;

  TomaActivaSesion({
    required this.tomaId,
    this.tiendaId,
    required this.tiendaNombre,
    required this.alcanceTexto,
    required this.fechaInicio,
    this.totalContados = 0,
    this.categoria,
    this.clase,
    this.subClase,
  });

  Map<String, dynamic> toJson() => {
        'tomaId': tomaId,
        'tiendaId': tiendaId,
        'tiendaNombre': tiendaNombre,
        'alcanceTexto': alcanceTexto,
        'fechaInicio': fechaInicio.toIso8601String(),
        'totalContados': totalContados,
        'categoria': categoria,
        'clase': clase,
        'subClase': subClase,
      };

  factory TomaActivaSesion.fromJson(Map<String, dynamic> json) => TomaActivaSesion(
        tomaId: json['tomaId']?.toString() ?? '',
        tiendaId: json['tiendaId'] as int?,
        tiendaNombre: json['tiendaNombre']?.toString() ?? 'Tienda',
        alcanceTexto: json['alcanceTexto']?.toString() ?? 'Toda la tienda',
        fechaInicio: json['fechaInicio'] != null
            ? DateTime.tryParse(json['fechaInicio'].toString()) ?? DateTime.now()
            : DateTime.now(),
        totalContados: (json['totalContados'] as num?)?.toInt() ?? 0,
        categoria: json['categoria']?.toString(),
        clase: json['clase']?.toString(),
        subClase: json['subClase']?.toString(),
      );
}

class TomaInventarioService {
  static final TomaInventarioService _instance = TomaInventarioService._internal();
  factory TomaInventarioService() => _instance;

  TomaInventarioService._internal() {
    _recuperarSesion();
  }

  static const String _storageKey = 'toma_inventario_sesion_activa';

  final ValueNotifier<TomaActivaSesion?> sesionActiva = ValueNotifier<TomaActivaSesion?>(null);

  bool get hayTomaActiva => sesionActiva.value != null;

  void _recuperarSesion() {
    try {
      if (kIsWeb) {
        final raw = html.window.localStorage[_storageKey];
        if (raw != null && raw.isNotEmpty) {
          final map = jsonDecode(raw);
          if (map is Map<String, dynamic>) {
            sesionActiva.value = TomaActivaSesion.fromJson(map);
          }
        }
      }
    } catch (e) {
      debugPrint('Error recuperando sesión de toma: $e');
    }
  }

  void _guardarEnStorage() {
    try {
      if (kIsWeb) {
        if (sesionActiva.value != null) {
          html.window.localStorage[_storageKey] = jsonEncode(sesionActiva.value!.toJson());
        } else {
          html.window.localStorage.remove(_storageKey);
        }
      }
    } catch (e) {
      debugPrint('Error guardando sesión de toma: $e');
    }
  }

  void iniciarSesion({
    required String tomaId,
    int? tiendaId,
    required String tiendaNombre,
    required String alcanceTexto,
    String? categoria,
    String? clase,
    String? subClase,
  }) {
    sesionActiva.value = TomaActivaSesion(
      tomaId: tomaId,
      tiendaId: tiendaId,
      tiendaNombre: tiendaNombre,
      alcanceTexto: alcanceTexto,
      fechaInicio: DateTime.now(),
      totalContados: 0,
      categoria: categoria,
      clase: clase,
      subClase: subClase,
    );
    _guardarEnStorage();
  }

  void actualizarProgreso({required int totalContados}) {
    if (sesionActiva.value != null) {
      sesionActiva.value!.totalContados = totalContados;
      sesionActiva.value = TomaActivaSesion(
        tomaId: sesionActiva.value!.tomaId,
        tiendaId: sesionActiva.value!.tiendaId,
        tiendaNombre: sesionActiva.value!.tiendaNombre,
        alcanceTexto: sesionActiva.value!.alcanceTexto,
        fechaInicio: sesionActiva.value!.fechaInicio,
        totalContados: totalContados,
        categoria: sesionActiva.value!.categoria,
        clase: sesionActiva.value!.clase,
        subClase: sesionActiva.value!.subClase,
      );
      _guardarEnStorage();
    }
  }

  void finalizarSesion() {
    sesionActiva.value = null;
    _guardarEnStorage();
  }

  void cancelarSesion() {
    sesionActiva.value = null;
    _guardarEnStorage();
  }

  /// Sincroniza el conteo actual desde Supabase si existe una sesión activa
  Future<void> sincronizarConteoDesdeBD() async {
    if (sesionActiva.value == null) return;
    try {
      final tomaId = sesionActiva.value!.tomaId;
      final res = await Supabase.instance.client
          .from('tomas_inventario_detalle')
          .select('id')
          .eq('toma_id', tomaId)
          .not('cantidad_contada', 'is', null);

      actualizarProgreso(totalContados: res.length);
    } catch (e) {
      debugPrint('Error sincronizando conteo desde BD: $e');
    }
  }
}
