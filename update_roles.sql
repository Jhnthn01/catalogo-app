ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'despachador';
ALTER TABLE public.detalles_pedido ADD COLUMN cantidad_despachada integer DEFAULT 0;
