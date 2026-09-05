import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/data/models/kardex_model.dart';

class KardexService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene los movimientos de Kardex para un producto dado,
  /// ordenados por created_at de forma descendente, haciendo JOIN con productos y tiendas.
  /// El nombre del usuario se resuelve en una segunda consulta a public.perfiles.
  Future<List<KardexMovimiento>> getMovimientosPorProducto(
    String productoId, {
    int? tiendaId,
  }) async {
    try {
      var query = _supabase
          .from('kardex_movimientos')
          .select('*, productos(sku, descripcion_1), tiendas(nombre)')
          .eq('producto_id', productoId);

      if (tiendaId != null) {
        query = query.eq('tienda_id', tiendaId);
      }

      final List<dynamic> data =
          await query.order('created_at', ascending: false);

      final movimientos = data
          .map((json) =>
              KardexMovimiento.fromJson(Map<String, dynamic>.from(json)))
          .toList();

      // Enriquecer con nombres de usuario desde public.perfiles (FK separada)
      await _enriquecerConNombresUsuario(movimientos);

      return movimientos;
    } catch (e) {
      debugPrint('Error en getMovimientosPorProducto: $e');
      rethrow;
    }
  }

  /// Resuelve nombres de usuario consultando public.perfiles por los usuario_id únicos.
  Future<void> _enriquecerConNombresUsuario(List<KardexMovimiento> movimientos) async {
    final ids = movimientos
        .map((m) => m.usuarioId)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final res = await _supabase
          .from('perfiles')
          .select('id, nombre')
          .inFilter('id', ids);
      final Map<String, String> nombresMap = {
        for (final p in res as List)
          p['id'].toString(): (p['nombre'] ?? '').toString()
      };
      for (int i = 0; i < movimientos.length; i++) {
        final uid = movimientos[i].usuarioId;
        if (uid != null && nombresMap.containsKey(uid)) {
          movimientos[i] = KardexMovimiento(
            id: movimientos[i].id,
            productoId: movimientos[i].productoId,
            tiendaId: movimientos[i].tiendaId,
            tipoMovimiento: movimientos[i].tipoMovimiento,
            origenTipo: movimientos[i].origenTipo,
            origenId: movimientos[i].origenId,
            cantidad: movimientos[i].cantidad,
            costoUnitario: movimientos[i].costoUnitario,
            stockAnterior: movimientos[i].stockAnterior,
            stockResultante: movimientos[i].stockResultante,
            costoMedioMomento: movimientos[i].costoMedioMomento,
            usuarioId: uid,
            createdAt: movimientos[i].createdAt,
            productoSku: movimientos[i].productoSku,
            productoDescripcion: movimientos[i].productoDescripcion,
            tiendaNombre: movimientos[i].tiendaNombre,
            usuarioNombre: nombresMap[uid],
          );
        }
      }
    } catch (e) {
      debugPrint('No se pudo enriquecer nombres de usuario: $e');
    }
  }

  /// Registra un nuevo movimiento en public.kardex_movimientos.
  /// Asigna automáticamente usuario_id actual si no viene provisto.
  /// Gestiona el cálculo y actualización de stock anterior y resultante.
  Future<KardexMovimiento> registrarMovimiento(
      KardexMovimiento movimiento) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      final usuarioIdFinal = movimiento.usuarioId ?? currentUserId;

      double? stockAnterior = movimiento.stockAnterior;
      double? stockResultante = movimiento.stockResultante;

      if (stockAnterior == null || stockResultante == null) {
        var invQuery = _supabase
            .from('inventario')
            .select('id, stock')
            .eq('producto_id', movimiento.productoId);

        if (movimiento.tiendaId != null) {
          invQuery = invQuery.eq('tienda_id', movimiento.tiendaId!);
        }

        final invList = await invQuery;
        if (invList.isNotEmpty) {
          final invRecord = invList.first;
          final double currStock =
              num.tryParse(invRecord['stock'].toString())?.toDouble() ?? 0.0;
          stockAnterior ??= currStock;

          if (movimiento.tipoMovimiento == 'ENTRADA') {
            stockResultante ??= stockAnterior + movimiento.cantidad;
          } else if (movimiento.tipoMovimiento == 'SALIDA') {
            stockResultante ??= stockAnterior - movimiento.cantidad;
          } else {
            stockResultante ??= stockAnterior;
          }

          await _supabase
              .from('inventario')
              .update({'stock': stockResultante})
              .eq('id', invRecord['id']);
        } else {
          stockAnterior ??= 0.0;
          if (movimiento.tipoMovimiento == 'ENTRADA') {
            stockResultante ??= movimiento.cantidad;
          } else if (movimiento.tipoMovimiento == 'SALIDA') {
            stockResultante ??= -movimiento.cantidad;
          } else {
            stockResultante ??= 0.0;
          }

          if (movimiento.tiendaId != null) {
            await _supabase.from('inventario').insert({
              'producto_id': movimiento.productoId,
              'tienda_id': movimiento.tiendaId,
              'stock': stockResultante,
            });
          }
        }
      }

      final movimientoFinal = KardexMovimiento(
        id: movimiento.id,
        productoId: movimiento.productoId,
        tiendaId: movimiento.tiendaId,
        tipoMovimiento: movimiento.tipoMovimiento,
        origenTipo: movimiento.origenTipo,
        origenId: movimiento.origenId,
        cantidad: movimiento.cantidad,
        costoUnitario: movimiento.costoUnitario,
        stockAnterior: stockAnterior,
        stockResultante: stockResultante,
        costoMedioMomento: movimiento.costoMedioMomento,
        usuarioId: usuarioIdFinal,
        createdAt: movimiento.createdAt,
      );

      final data = await _supabase
          .from('kardex_movimientos')
          .insert(movimientoFinal.toJson())
          .select('*, productos(sku, descripcion_1), tiendas(nombre)')
          .single();

      return KardexMovimiento.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('Error registrando movimiento kardex: $e');
      rethrow;
    }
  }
}
