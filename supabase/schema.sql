-- Habilitar extensión UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Eliminar tablas y tipos si existen para poder ejecutar el script varias veces (opcional)
DROP TABLE IF EXISTS center_needs;
DROP TABLE IF EXISTS centers;
DROP TABLE IF EXISTS profiles;
DROP TYPE IF EXISTS user_role;
DROP TYPE IF EXISTS category_type;

-- Crear tipos personalizados
CREATE TYPE user_role AS ENUM ('super_admin', 'manager');
CREATE TYPE category_type AS ENUM ('Ropa', 'Medicina', 'Agua', 'Comida');

-- Tabla de perfiles
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role user_role NOT NULL DEFAULT 'manager',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Tabla de centros
CREATE TABLE centers (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT NOT NULL,
  contact TEXT NOT NULL,
  manager_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Tabla de necesidades de los centros
CREATE TABLE center_needs (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  center_id UUID REFERENCES centers(id) ON DELETE CASCADE NOT NULL,
  category category_type NOT NULL,
  active BOOLEAN DEFAULT true NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(center_id, category) -- Asegura una entrada por categoría por centro
);

-- Configuración de Seguridad a Nivel de Filas (RLS)

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

-- Profiles
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Cualquiera puede ver los perfiles" ON profiles FOR SELECT USING (true);
CREATE POLICY "Usuarios pueden insertar su propio perfil" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Usuarios pueden actualizar su propio perfil" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Super admins insert profile" ON profiles FOR INSERT WITH CHECK (public.is_super_admin());
CREATE POLICY "Super admins update profile" ON profiles FOR UPDATE USING (public.is_super_admin());
CREATE POLICY "Super admins delete profile" ON profiles FOR DELETE USING (public.is_super_admin());

-- Centers
ALTER TABLE centers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Cualquiera puede ver los centros" ON centers FOR SELECT USING (true);
CREATE POLICY "Solo super admins pueden crear centros" ON centers FOR INSERT WITH CHECK (public.is_super_admin());
CREATE POLICY "Solo super admins pueden modificar centros" ON centers FOR UPDATE USING (public.is_super_admin());
CREATE POLICY "Solo super admins pueden eliminar centros" ON centers FOR DELETE USING (public.is_super_admin());

-- Center needs
ALTER TABLE center_needs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Cualquiera puede ver las necesidades" ON center_needs FOR SELECT USING (true);
CREATE POLICY "Super admins insert needs" ON center_needs FOR INSERT WITH CHECK (public.is_super_admin());
CREATE POLICY "Super admins update needs" ON center_needs FOR UPDATE USING (public.is_super_admin());
CREATE POLICY "Super admins delete needs" ON center_needs FOR DELETE USING (public.is_super_admin());
CREATE POLICY "Gestores pueden actualizar las necesidades de sus centros" ON center_needs FOR UPDATE USING (
  EXISTS (SELECT 1 FROM centers c WHERE c.id = center_id AND c.manager_id = auth.uid())
);
