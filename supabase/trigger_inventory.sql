-- Trigger: al recibir un envío, actualizar inventario de ambos centros
-- Ejecutar en Supabase SQL Editor (después de inventory.sql)

CREATE OR REPLACE FUNCTION on_shipment_update_inventory()
RETURNS TRIGGER AS $$
DECLARE
  item_record RECORD;
  mat_id UUID;
  item_qty INTEGER;
BEGIN
  -- Solo al marcar como recibido
  IF NEW.status = 'received' AND OLD.status != 'received' THEN
    -- Recorrer cada item del envío
    FOR item_record IN SELECT * FROM jsonb_each_text(NEW.items)
    LOOP
      item_qty := item_record.value::INTEGER;
      IF item_qty <= 0 THEN CONTINUE; END IF;

      -- Buscar material por nombre (o crear si no existe)
      SELECT id INTO mat_id FROM materials WHERE name = item_record.key;
      
      IF mat_id IS NOT NULL THEN
        -- Restar del centro origen (si hay suficiente)
        INSERT INTO center_inventory (center_id, material_id, quantity)
        VALUES (NEW.from_center_id, mat_id, 0)
        ON CONFLICT (center_id, material_id) DO NOTHING;

        UPDATE center_inventory 
        SET quantity = GREATEST(quantity - item_qty, 0), updated_at = NOW()
        WHERE center_id = NEW.from_center_id AND material_id = mat_id;

        -- Sumar al centro destino
        INSERT INTO center_inventory (center_id, material_id, quantity)
        VALUES (NEW.to_center_id, mat_id, item_qty)
        ON CONFLICT (center_id, material_id) 
        DO UPDATE SET quantity = center_inventory.quantity + item_qty, updated_at = NOW();
      END IF;
    END LOOP;

    -- Marcar necesidades del centro destino como cubiertas (trigger existente)
    UPDATE center_needs 
    SET active = false, updated_at = NOW()
    WHERE center_id = NEW.to_center_id 
      AND category IN (
        SELECT key FROM jsonb_each_text(NEW.items) WHERE value::int > 0
      );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS shipment_inventory_trigger ON shipments;

CREATE TRIGGER shipment_inventory_trigger
  AFTER UPDATE ON shipments
  FOR EACH ROW
  EXECUTE FUNCTION on_shipment_update_inventory();

-- También eliminar el trigger viejo de receive (ya está integrado acá)
DROP TRIGGER IF EXISTS shipment_received_trigger ON shipments;
