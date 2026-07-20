-- Tablas de inventario por centro de acopio
-- Ejecutar en Supabase SQL Editor

-- Tipos de materiales
CREATE TABLE materials (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  emoji TEXT DEFAULT '📦',
  unit TEXT DEFAULT 'unidades',     -- kg, litros, cajas, unidades, etc.
  category TEXT,                     -- agrupación opcional (Alimentos, Higiene, etc.)
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Inventario por centro
CREATE TABLE center_inventory (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  center_id UUID REFERENCES centers(id) ON DELETE CASCADE NOT NULL,
  material_id UUID REFERENCES materials(id) ON DELETE CASCADE NOT NULL,
  quantity INTEGER DEFAULT 0 NOT NULL CHECK (quantity >= 0),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(center_id, material_id)
);

-- Índices
CREATE INDEX idx_inventory_center ON center_inventory(center_id);
CREATE INDEX idx_inventory_material ON center_inventory(material_id);

-- RLS
ALTER TABLE materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE center_inventory ENABLE ROW LEVEL SECURITY;

-- Cualquiera puede ver materiales e inventario
CREATE POLICY "Cualquiera puede ver materiales" ON materials FOR SELECT USING (true);
CREATE POLICY "Cualquiera puede ver inventario" ON center_inventory FOR SELECT USING (true);

-- Solo super admins pueden crear/modificar materiales
CREATE POLICY "Super admins gestionan materiales" ON materials FOR ALL USING (public.is_super_admin());

-- Super admins y gestores del centro pueden modificar inventario
CREATE POLICY "Super admins y gestores modifican inventario" ON center_inventory FOR ALL 
USING (
  public.is_super_admin() 
  OR EXISTS (
    SELECT 1 FROM centers c WHERE c.id = center_id AND c.manager_id = auth.uid()
  )
);

-- Seed: 4 materiales por defecto
INSERT INTO materials (name, emoji, unit, category) VALUES
  ('Ropa', '👕', 'unidades', 'Donaciones'),
  ('Medicina', '💊', 'unidades', 'Salud'),
  ('Agua', '💧', 'litros', 'Alimentos'),
  ('Comida', '🍎', 'kg', 'Alimentos')
ON CONFLICT (name) DO NOTHING;
