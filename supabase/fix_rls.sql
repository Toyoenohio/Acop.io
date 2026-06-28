-- Eliminar la política recursiva que causa el error
DROP POLICY IF EXISTS "Super admins pueden administrar todos los perfiles" ON profiles;

-- Crear una función segura que verifica si alguien es super_admin (bypasses RLS)
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'super_admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recrear las políticas usando la función segura para evitar la recursión

-- Política para que los super admins puedan insertar en Profiles (si alguna vez se necesita)
CREATE POLICY "Super admins insert" ON profiles 
FOR INSERT WITH CHECK (public.is_super_admin());

-- Política para que los super admins puedan actualizar cualquier Profile
CREATE POLICY "Super admins update" ON profiles 
FOR UPDATE USING (public.is_super_admin());

-- Política para que los super admins puedan eliminar cualquier Profile
CREATE POLICY "Super admins delete" ON profiles 
FOR DELETE USING (public.is_super_admin());
