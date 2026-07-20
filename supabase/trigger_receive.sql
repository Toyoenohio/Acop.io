-- Trigger: al recibir un envío, marcar necesidades del centro destino como cubiertas
-- Ejecutar en Supabase SQL Editor (después de shipments.sql)

CREATE OR REPLACE FUNCTION on_shipment_received()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'received' AND OLD.status != 'received' THEN
    UPDATE center_needs 
    SET active = false, updated_at = NOW()
    WHERE center_id = NEW.to_center_id 
      AND category IN (
        SELECT key 
        FROM jsonb_each_text(NEW.items) 
        WHERE value::int > 0
      );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS shipment_received_trigger ON shipments;

CREATE TRIGGER shipment_received_trigger
  AFTER UPDATE ON shipments
  FOR EACH ROW
  EXECUTE FUNCTION on_shipment_received();
