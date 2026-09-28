-- ============================================================================
-- Función RPC: confirmar_venta_catalogo
-- Descripción: Registra un pedido, sus detalles, descuenta inventario y
--              genera los movimientos correspondientes en kardex_movimientos
--              de forma 100% atómica.
-- ============================================================================

-- Limpiar versiones anteriores para evitar conflictos de firma
DROP FUNCTION IF EXISTS public.confirmar_venta_catalogo(integer, jsonb, uuid, text, text, text, text, text, text, text, timestamp with time zone, text, text, numeric);
DROP FUNCTION IF EXISTS public.confirmar_venta_catalogo(integer, jsonb, text, text, text, text, text, text, text, timestamp with time zone, text, text, numeric);
DROP FUNCTION IF EXISTS public.confirmar_venta_catalogo(integer, jsonb, text, text, text, text, text, text, text, timestamp with time zone, text, text, numeric, boolean);
DROP FUNCTION IF EXISTS public.confirmar_venta_catalogo;

CREATE OR REPLACE FUNCTION public.confirmar_venta_catalogo(
  p_tienda_id integer,
  p_items jsonb,
  p_nombre_cliente text DEFAULT NULL,
  p_telefono_cliente text DEFAULT NULL,
  p_direccion_cliente text DEFAULT NULL,
  p_tipo_documento text DEFAULT NULL,
  p_numero_documento text DEFAULT NULL,
  p_tipo_comprobante text DEFAULT 'Nota de Venta',
  p_forma_pago text DEFAULT 'Efectivo',
  p_fecha_entrega timestamp with time zone DEFAULT now(),
  p_segundo_recoge text DEFAULT NULL,
  p_estado text DEFAULT 'entregado',
  p_total numeric DEFAULT NULL,
  p_descontar_stock boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_usuario_id uuid;
  v_pedido_id uuid;
  v_total numeric := 0;
  v_total_calculado numeric := 0;
  v_requiere_regularizacion boolean := false;
  v_item jsonb;
  v_producto_id uuid;
  v_cantidad numeric;
  v_precio_unitario numeric;
  v_inv_id uuid;
  v_stock_anterior numeric;
  v_stock_resultante numeric;
  v_costo_unitario numeric;
BEGIN
  -- 1. Validar autenticación estricta con auth.uid()
  v_usuario_id := auth.uid();
  IF v_usuario_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado. Se requiere una sesión activa.';
  END IF;

  -- 2. Validar que la tienda exista
  IF p_tienda_id IS NULL THEN
    RAISE EXCEPTION 'El parámetro p_tienda_id es obligatorio';
  END IF;

  -- 3. Validar items
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La lista de items no puede estar vacía';
  END IF;

  -- 4. Pre-calcular total y verificar si requerirá regularización
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_producto_id := (v_item->>'producto_id')::uuid;
    v_cantidad := coalesce((v_item->>'cantidad')::numeric, 0);
    v_precio_unitario := coalesce((v_item->>'precio_unitario')::numeric, 0);

    IF v_cantidad <= 0 THEN
      RAISE EXCEPTION 'La cantidad para el producto % debe ser mayor a 0', v_producto_id;
    END IF;

    v_total_calculado := v_total_calculado + (v_cantidad * v_precio_unitario);

    -- Revisar stock actual de la tienda para determinar requerimiento de regularización
    SELECT stock INTO v_stock_anterior
    FROM public.inventario
    WHERE producto_id = v_producto_id AND tienda_id = p_tienda_id;

    IF v_stock_anterior IS NULL OR v_stock_anterior < v_cantidad THEN
      v_requiere_regularizacion := true;
    END IF;
  END LOOP;

  v_total := coalesce(p_total, v_total_calculado);

  -- 5. Insertar la cabecera en la tabla pedidos
  INSERT INTO public.pedidos (
    usuario_id,
    tienda_id,
    total,
    estado,
    total_despachado,
    nombre_cliente,
    telefono_cliente,
    direccion_cliente,
    tipo_documento,
    numero_documento,
    tipo_comprobante,
    forma_pago,
    fecha_entrega,
    segundo_recoge,
    requiere_regularizacion,
    created_at
  ) VALUES (
    v_usuario_id,
    p_tienda_id,
    v_total,
    coalesce(p_estado, 'entregado'),
    CASE WHEN coalesce(p_estado, 'entregado') = 'entregado' THEN v_total ELSE NULL END,
    p_nombre_cliente,
    p_telefono_cliente,
    p_direccion_cliente,
    p_tipo_documento,
    p_numero_documento,
    coalesce(p_tipo_comprobante, 'Nota de Venta'),
    coalesce(p_forma_pago, 'Efectivo'),
    coalesce(p_fecha_entrega, now()),
    p_segundo_recoge,
    v_requiere_regularizacion,
    now()
  )
  RETURNING id INTO v_pedido_id;

  -- 6. Procesar cada item: detalles_pedido, actualización de inventario y Kardex
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_producto_id := (v_item->>'producto_id')::uuid;
    v_cantidad := (v_item->>'cantidad')::numeric;
    v_precio_unitario := (v_item->>'precio_unitario')::numeric;

    -- a. Insertar fila en detalles_pedido (siempre se ejecuta)
    INSERT INTO public.detalles_pedido (
      pedido_id,
      producto_id,
      cantidad,
      precio_unitario,
      cantidad_despachada
    ) VALUES (
      v_pedido_id,
      v_producto_id,
      v_cantidad,
      v_precio_unitario,
      CASE WHEN coalesce(p_estado, 'entregado') = 'entregado' THEN v_cantidad ELSE NULL END
    );

    -- b. Descontar stock y registrar Kardex solo si p_descontar_stock es true
    IF p_descontar_stock THEN
      -- Bloquear y leer fila de inventario para consistencia concurrente
      SELECT id, stock
      INTO v_inv_id, v_stock_anterior
      FROM public.inventario
      WHERE producto_id = v_producto_id AND tienda_id = p_tienda_id
      FOR UPDATE;

      IF v_inv_id IS NOT NULL THEN
        v_stock_anterior := coalesce(v_stock_anterior, 0);
        v_stock_resultante := v_stock_anterior - v_cantidad;

        UPDATE public.inventario
        SET 
          stock = v_stock_resultante,
          actualizado_at = now(),
          usuario_id = v_usuario_id
        WHERE id = v_inv_id;
      ELSE
        v_stock_anterior := 0;
        v_stock_resultante := -v_cantidad;

        INSERT INTO public.inventario (
          producto_id,
          tienda_id,
          stock,
          actualizado_at,
          usuario_id
        ) VALUES (
          v_producto_id,
          p_tienda_id,
          v_stock_resultante,
          now(),
          v_usuario_id
        );
      END IF;

      -- Obtener costo del producto para registrar en Kardex
      SELECT coalesce(costo_medio, ultimo_costo, costo, 0)
      INTO v_costo_unitario
      FROM public.productos
      WHERE id = v_producto_id;

      -- Registrar movimiento SALIDA en kardex_movimientos
      INSERT INTO public.kardex_movimientos (
        producto_id,
        tienda_id,
        tipo_movimiento,
        origen_tipo,
        origen_id,
        cantidad,
        costo_unitario,
        stock_anterior,
        stock_resultante,
        costo_medio_momento,
        usuario_id,
        created_at
      ) VALUES (
        v_producto_id,
        p_tienda_id,
        'SALIDA',
        'PEDIDO',
        v_pedido_id,
        v_cantidad,
        coalesce(v_costo_unitario, 0),
        v_stock_anterior,
        v_stock_resultante,
        coalesce(v_costo_unitario, 0),
        v_usuario_id,
        now()
      );
    END IF;
  END LOOP;

  -- 7. Retornar el pedido recién creado en formato JSON
  RETURN jsonb_build_object(
    'success', true,
    'pedido_id', v_pedido_id,
    'pedido', (SELECT to_jsonb(p.*) FROM public.pedidos p WHERE p.id = v_pedido_id)
  );

EXCEPTION
  WHEN OTHERS THEN
    -- Postgres revierte automáticamente toda la transacción en caso de excepción
    RAISE;
END;
$$;

-- Restringir permisos de ejecución únicamente al rol authenticated
REVOKE EXECUTE ON FUNCTION public.confirmar_venta_catalogo FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirmar_venta_catalogo TO authenticated;

-- Notificar a PostgREST para recargar la caché del esquema
NOTIFY pgrst, 'reload schema';
