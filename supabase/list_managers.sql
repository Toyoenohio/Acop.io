-- Función segura para listar gestores con email
-- La usa el admin para el dropdown de asignación.
-- Ejecutar en Supabase SQL Editor.

CREATE OR REPLACE FUNCTION list_managers()
RETURNS TABLE (
  id UUID,
  email VARCHAR(255),
  role public.user_role,
  created_at TIMESTAMPTZ
)
SECURITY DEFINER
SET search_path = ''
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, u.email, p.role, p.created_at
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE p.role = 'manager'
  ORDER BY p.created_at DESC;
END;
$$;

-- Permiso para que el rol autenticado (super_admin) pueda llamarla
GRANT EXECUTE ON FUNCTION list_managers() TO authenticated;
