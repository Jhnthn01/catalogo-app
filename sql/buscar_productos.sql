-- Script SQL corregido para Supabase
-- EL ERROR 400 SE DEBÍA A QUE public.productos.id ES DE TIPO uuid Y NO bigint.

-- 1. Asegurar columna fecha_ultimo_costo en productos
ALTER TABLE public.productos 
ADD COLUMN IF NOT EXISTS fecha_ultimo_costo timestamp with time zone;

-- 2. Eliminar versiones anteriores para evitar conflictos de tipo o firma
DROP FUNCTION IF EXISTS public.buscar_productos(text[], bigint, text, text, text, integer, integer);
DROP FUNCTION IF EXISTS public.buscar_productos(text[], bigint, text, text, text, integer, integer, text);
DROP FUNCTION IF EXISTS public.buscar_productos(text[], integer, text, text, text, integer, integer);
DROP FUNCTION IF EXISTS public.buscar_productos(text[], integer, text, text, text, integer, integer, text);
DROP FUNCTION IF EXISTS public.buscar_productos;

-- 3. Crear la función con la definición exacta de tipos de la tabla productos (id uuid, p_tienda_id integer)
CREATE OR REPLACE FUNCTION public.buscar_productos(
  p_tokens text[],
  p_tienda_id integer DEFAULT NULL,
  p_categoria text DEFAULT NULL,
  p_clase text DEFAULT NULL,
  p_sub_clase text DEFAULT NULL,
  p_limit integer DEFAULT 500,
  p_offset integer DEFAULT 0,
  p_modo text DEFAULT 'cualquiera'
)
RETURNS TABLE (
  id uuid,
  sku text,
  upc text,
  alu text,
  marca text,
  categoria text,
  clase text,
  sub_clase text,
  estilo text,
  descripcion_1 text,
  descripcion_2 text,
  color text,
  costo numeric,
  precio_venta numeric,
  ultimo_costo numeric,
  fecha_ultimo_costo timestamp with time zone,
  costo_medio numeric,
  inventario jsonb
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.sku,
    p.upc,
    p.alu,
    p.marca,
    p.categoria,
    p.clase,
    p.sub_clase,
    p.estilo,
    p.descripcion_1,
    p.descripcion_2,
    p.color,
    p.costo,
    p.precio_venta,
    p.ultimo_costo,
    coalesce(
      p.fecha_ultimo_costo,
      (
        SELECT km.created_at 
        FROM public.kardex_movimientos km 
        WHERE km.producto_id = p.id AND km.costo_unitario > 0 
        ORDER BY km.created_at DESC 
        LIMIT 1
      ),
      p.created_at
    ) AS fecha_ultimo_costo,
    p.costo_medio,
    CASE 
      WHEN p_tienda_id IS NOT NULL THEN
        coalesce(
          (SELECT jsonb_agg(jsonb_build_object('stock', i.stock, 'tienda_id', i.tienda_id))
           FROM public.inventario i
           WHERE i.producto_id = p.id AND i.tienda_id = p_tienda_id),
          '[]'::jsonb
        )
      ELSE
        coalesce(
          (SELECT jsonb_agg(jsonb_build_object('stock', i.stock, 'tienda_id', i.tienda_id))
           FROM public.inventario i
           WHERE i.producto_id = p.id),
          '[]'::jsonb
        )
    END AS inventario
  FROM public.productos p
  WHERE 
    (p_categoria IS NULL OR p.categoria = p_categoria)
    AND (p_clase IS NULL OR p.clase = p_clase)
    AND (p_sub_clase IS NULL OR p.sub_clase = p_sub_clase)
    AND (
      p_tienda_id IS NULL 
      OR EXISTS (
        SELECT 1 FROM public.inventario i 
        WHERE i.producto_id = p.id AND i.tienda_id = p_tienda_id
      )
    )
    AND (
      cardinality(p_tokens) = 0
      OR (
        LOWER(coalesce(p_modo, 'cualquiera')) = 'todas' AND NOT EXISTS (
          SELECT 1 
          FROM unnest(p_tokens) tok 
          WHERE LOWER(
            coalesce(p.descripcion_1, '') || ' ' || 
            coalesce(p.sku, '') || ' ' || 
            coalesce(p.upc, '') || ' ' || 
            coalesce(p.marca, '') || ' ' || 
            coalesce(p.alu, '')
          ) NOT LIKE '%' || LOWER(tok) || '%'
        )
      )
      OR (
        LOWER(coalesce(p_modo, 'cualquiera')) != 'todas' AND EXISTS (
          SELECT 1 
          FROM unnest(p_tokens) tok 
          WHERE LOWER(
            coalesce(p.descripcion_1, '') || ' ' || 
            coalesce(p.sku, '') || ' ' || 
            coalesce(p.upc, '') || ' ' || 
            coalesce(p.marca, '') || ' ' || 
            coalesce(p.alu, '')
          ) LIKE '%' || LOWER(tok) || '%'
        )
      )
    )
  ORDER BY p.descripcion_1
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- 3. Notificar a PostgREST para recargar la caché del esquema
NOTIFY pgrst, 'reload schema';
