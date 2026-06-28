-- Habilitar Supabase Realtime en la tabla center_needs
-- Esto permite que los cambios se reflejen en tiempo real en el frontend.
-- Ejecutar en Supabase SQL Editor.

ALTER PUBLICATION supabase_realtime ADD TABLE public.center_needs;
