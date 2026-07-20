-- Tabla de envíos entre centros de acopio
-- Ejecutar en Supabase SQL Editor

CREATE TYPE shipment_status AS ENUM ('pending', 'in_transit', 'received', 'cancelled');

CREATE TABLE shipments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  from_center_id UUID REFERENCES centers(id) ON DELETE CASCADE NOT NULL,
  to_center_id UUID REFERENCES centers(id) ON DELETE CASCADE NOT NULL,
  status shipment_status DEFAULT 'pending' NOT NULL,
  items JSONB NOT NULL DEFAULT '{}',
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  received_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  received_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX idx_shipments_code ON shipments(code);
CREATE INDEX idx_shipments_from ON shipments(from_center_id);
CREATE INDEX idx_shipments_to ON shipments(to_center_id);
CREATE INDEX idx_shipments_status ON shipments(status);

ALTER TABLE shipments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede ver envíos" ON shipments FOR SELECT USING (true);

CREATE POLICY "Super admins y gestores pueden crear envíos" ON shipments FOR INSERT 
WITH CHECK (
  public.is_super_admin() 
  OR EXISTS (
    SELECT 1 FROM centers c WHERE c.id = from_center_id AND c.manager_id = auth.uid()
  )
);

CREATE POLICY "Super admins y gestores pueden actualizar envíos" ON shipments FOR UPDATE 
USING (
  public.is_super_admin() 
  OR EXISTS (
    SELECT 1 FROM centers c WHERE c.id = to_center_id AND c.manager_id = auth.uid()
  )
);
