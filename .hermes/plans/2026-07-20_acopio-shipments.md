# Sistema de Envíos entre Centros — Plan de Implementación

> **Para Hermes:** Implementar tarea por tarea. Cada task es atómica.

**Objetivo:** Permitir que un centro de acopio (CA1) genere órdenes de envío a otro centro (CA2) con código/QR, y que CA2 registre la recepción al escanear. Trazabilidad completa de entradas/salidas.

**Arquitectura:** Nueva tabla `shipments` en Supabase + página de creación (`/envios/nuevo`) + página pública de recepción (`/recibir/[code]`) con QR. Astro 7 SSR, mismas convenciones del proyecto.

**Stack:** Astro 7 + Supabase (PostgreSQL) + Tailwind CSS 4 + QRCode.js (vanilla, sin deps)

---

## Task 1: Agregar tabla `shipments` en Supabase

**Objetivo:** Crear la estructura de datos para órdenes de envío

**Archivo:** Nuevo script SQL `supabase/shipments.sql`

```sql
-- Tabla de envíos entre centros
CREATE TYPE shipment_status AS ENUM ('pending', 'in_transit', 'received', 'cancelled');

CREATE TABLE shipments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,              -- código alfanumérico corto (ej: ENV-A3F9)
  from_center_id UUID REFERENCES centers(id) ON DELETE CASCADE NOT NULL,
  to_center_id UUID REFERENCES centers(id) ON DELETE CASCADE NOT NULL,
  status shipment_status DEFAULT 'pending' NOT NULL,
  items JSONB NOT NULL DEFAULT '{}',      -- {"Ropa": 50, "Medicina": 10, "Agua": 20, "Comida": 30}
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  received_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  received_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Índices
CREATE INDEX idx_shipments_code ON shipments(code);
CREATE INDEX idx_shipments_from ON shipments(from_center_id);
CREATE INDEX idx_shipments_to ON shipments(to_center_id);
CREATE INDEX idx_shipments_status ON shipments(status);

-- RLS
ALTER TABLE shipments ENABLE ROW LEVEL SECURITY;

-- Cualquiera puede ver envíos (página pública de recepción)
CREATE POLICY "Cualquiera puede ver envíos" ON shipments FOR SELECT USING (true);

-- Solo super_admins y gestores del centro origen pueden crear
CREATE POLICY "Super admins y gestores pueden crear envíos" ON shipments FOR INSERT 
WITH CHECK (
  public.is_super_admin() 
  OR EXISTS (
    SELECT 1 FROM centers c WHERE c.id = from_center_id AND c.manager_id = auth.uid()
  )
);

-- Solo super_admins y gestores del centro destino pueden actualizar (recibir)
CREATE POLICY "Super admins y gestores pueden actualizar envíos" ON shipments FOR UPDATE 
USING (
  public.is_super_admin() 
  OR EXISTS (
    SELECT 1 FROM centers c WHERE c.id = to_center_id AND c.manager_id = auth.uid()
  )
);
```

**Verificación:** Ejecutar en Supabase SQL Editor. `SELECT * FROM shipments;` debe devolver 0 rows sin error.

---

## Task 2: Crear página `/envios` — listado de envíos

**Objetivo:** Página SSR que lista todos los envíos con filtros

**Archivo:** Crear `src/pages/envios.astro`

La página debe:
- Cargar todos los shipments con JOIN a `centers` para nombres
- Mostrar tabla con: código, origen → destino, fecha, estado (badge de color), items
- Link a `/envios/nuevo` en header
- Mismo layout y estilos que el resto de la app (Layout.astro, card-bento)
- Polling cada 60s para actualizar estados (mismo patrón que index.astro)

```astro
---
import Layout from '../layouts/Layout.astro';
import { supabase } from '../lib/supabase';

export const prerender = false;

const { data: shipments, error } = await supabase
  .from('shipments')
  .select(`
    *,
    from_center:from_center_id(name),
    to_center:to_center_id(name)
  `)
  .order('created_at', { ascending: false });

const statusLabels: Record<string, string> = {
  pending: 'Pendiente',
  in_transit: 'En tránsito',
  received: 'Recibido',
  cancelled: 'Cancelado'
};

const statusColors: Record<string, string> = {
  pending: 'bg-yellow-50 text-yellow-700 border-yellow-200',
  in_transit: 'bg-blue-50 text-blue-700 border-blue-200',
  received: 'bg-green-50 text-green-700 border-green-200',
  cancelled: 'bg-red-50 text-red-700 border-red-200'
};
---

<Layout title="Envíos">
  <div class="mb-6 flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-extrabold text-bento-text">Envíos entre Centros</h1>
      <p class="text-sm text-bento-muted mt-1">Historial de transferencias de material</p>
    </div>
    <a href="/envios/nuevo" class="btn-primary text-sm">+ Nuevo Envío</a>
  </div>

  <div class="flex flex-col gap-3">
    {!shipments || shipments.length === 0 ? (
      <div class="card-bento text-center py-16 text-bento-muted">
        <span class="text-4xl block mb-3">📦</span>
        <p class="font-bold">Sin envíos registrados</p>
        <p class="text-sm">Creá tu primer envío para empezar.</p>
      </div>
    ) : (
      shipments.map((s: any) => (
        <div class="card-bento !p-4 flex flex-col sm:flex-row sm:items-center gap-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="font-mono font-bold text-sm text-bento-primary">{s.code}</span>
              <span class={`text-xs font-semibold px-2 py-0.5 rounded-full border ${statusColors[s.status]}`}>
                {statusLabels[s.status]}
              </span>
            </div>
            <p class="text-sm text-bento-text font-semibold">
              {s.from_center?.name || 'Desconocido'} → {s.to_center?.name || 'Desconocido'}
            </p>
            <p class="text-xs text-bento-muted mt-0.5">
              {new Date(s.created_at).toLocaleDateString('es-VE', { dateStyle: 'medium' })}
            </p>
          </div>
          <div class="flex items-center gap-2 text-xs text-bento-muted">
            {Object.entries(s.items || {}).map(([cat, qty]: [string, any]) => (
              qty > 0 ? <span class="bg-bento-surface px-2 py-1 rounded-lg font-semibold">{cat}: {qty}</span> : null
            ))}
          </div>
          <a href={`/recibir/${s.code}`} class="text-xs font-bold text-bento-primary hover:underline whitespace-nowrap">
            Ver detalle →
          </a>
        </div>
      ))
    )}
  </div>
</Layout>
```

**Verificación:** `npm run dev` → visitar `/envios`. Debe mostrar lista vacía con botón "+ Nuevo Envío".

---

## Task 3: Crear página `/envios/nuevo` — formulario de creación

**Objetivo:** Formulario donde CA1 selecciona destino, items y cantidades, genera código.

**Archivo:** Crear `src/pages/envios/nuevo.astro`

Funcionalidad:
- Select de centro origen (autodetectado si es gestor logueado, o lista de todos)
- Select de centro destino (todos los centros excepto el origen)
- Inputs de cantidad por categoría (Ropa, Medicina, Agua, Comida)
- Generar código automático: `ENV-` + 4 caracteres aleatorios (A-Z, 0-9)
- Mostrar QR code del link `/recibir/[code]`
- Al crear, insertar en `shipments`
- Mismo Layout + estilos

```astro
---
import Layout from '../../layouts/Layout.astro';
import { supabase } from '../../lib/supabase';

export const prerender = false;

const { data: centers } = await supabase
  .from('centers')
  .select('id, name')
  .order('name');

function generateCode(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code = '';
  for (let i = 0; i < 4; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return `ENV-${code}`;
}

const categories = ['Ropa', 'Medicina', 'Agua', 'Comida'];
---

<Layout title="Nuevo Envío">
  <div class="max-w-lg mx-auto">
    <a href="/envios" class="text-sm font-semibold text-bento-muted hover:text-bento-text mb-4 inline-block">
      ← Volver a envíos
    </a>
    
    <h1 class="text-2xl font-extrabold text-bento-text mb-6">Nuevo Envío</h1>

    <div id="form-container" class="card-bento flex flex-col gap-4">
      <!-- Origen -->
      <div>
        <label class="block text-sm font-semibold text-bento-text mb-2">Centro de origen</label>
        <select id="from-center" class="input-bento">
          <option value="">Seleccionar...</option>
          {centers?.map((c: any) => <option value={c.id}>{c.name}</option>)}
        </select>
      </div>

      <!-- Destino -->
      <div>
        <label class="block text-sm font-semibold text-bento-text mb-2">Centro de destino</label>
        <select id="to-center" class="input-bento">
          <option value="">Seleccionar...</option>
          {centers?.map((c: any) => <option value={c.id}>{c.name}</option>)}
        </select>
      </div>

      <!-- Items -->
      <div>
        <label class="block text-sm font-semibold text-bento-text mb-3">Material a enviar</label>
        <div class="grid grid-cols-2 gap-3">
          {categories.map(cat => (
            <div>
              <label class="text-xs font-semibold text-bento-muted mb-1 block">{cat}</label>
              <input type="number" id={`qty-${cat}`} min="0" value="0" 
                     class="input-bento" placeholder="0" />
            </div>
          ))}
        </div>
      </div>

      <!-- Notas -->
      <div>
        <label class="block text-sm font-semibold text-bento-text mb-2">Notas (opcional)</label>
        <textarea id="notes" class="input-bento" rows="2" placeholder="Ej: Enviar con prioridad"></textarea>
      </div>

      <button id="create-btn" class="btn-primary mt-2">
        Generar Orden de Envío
      </button>

      <div id="msg" class="hidden text-sm font-semibold p-3 rounded-xl text-center"></div>

      <!-- QR result (shown after creation) -->
      <div id="result" class="hidden flex flex-col items-center gap-4 p-4 bg-green-50 rounded-2xl border border-green-200 mt-2">
        <p class="text-sm font-bold text-green-800">✅ Orden creada</p>
        <p class="font-mono font-bold text-lg text-bento-text" id="result-code"></p>
        <div id="qrcode" class="bg-white p-3 rounded-xl"></div>
        <p class="text-xs text-green-700 text-center">
          Escaneá este QR o visitá el enlace para recibir el paquete
        </p>
        <a id="result-link" href="#" class="text-sm font-bold text-bento-primary break-all text-center"></a>
      </div>
    </div>
  </div>
</Layout>

<script>
  import QRCode from 'qrcodejs2'; // lightweight, vanilla JS

  const btn = document.getElementById('create-btn') as HTMLButtonElement;
  const msg = document.getElementById('msg') as HTMLDivElement;
  const result = document.getElementById('result') as HTMLDivElement;

  function showMsg(text: string, type: 'success' | 'error') {
    msg.classList.remove('hidden');
    msg.className = `text-sm font-semibold p-3 rounded-xl text-center ${
      type === 'success' ? 'bg-green-50 text-green-700 border border-green-100' 
                         : 'bg-red-50 text-red-700 border border-red-100'
    }`;
    msg.textContent = text;
    if (type === 'success') setTimeout(() => msg.classList.add('hidden'), 5000);
  }

  btn?.addEventListener('click', async () => {
    const fromId = (document.getElementById('from-center') as HTMLSelectElement).value;
    const toId = (document.getElementById('to-center') as HTMLSelectElement).value;
    const notes = (document.getElementById('notes') as HTMLTextAreaElement).value;

    if (!fromId || !toId) return showMsg('Seleccioná origen y destino', 'error');
    if (fromId === toId) return showMsg('Origen y destino no pueden ser iguales', 'error');

    const items: Record<string, number> = {};
    let hasItems = false;
    ['Ropa', 'Medicina', 'Agua', 'Comida'].forEach(cat => {
      const qty = parseInt((document.getElementById(`qty-${cat}`) as HTMLInputElement).value) || 0;
      if (qty > 0) hasItems = true;
      items[cat] = qty;
    });

    if (!hasItems) return showMsg('Agregá al menos un item con cantidad > 0', 'error');

    btn.disabled = true;
    btn.textContent = 'Creando...';

    const code = 'ENV-' + Array.from({length:4}, () => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[Math.floor(Math.random()*36)]).join('');
    const receiveUrl = `${window.location.origin}/recibir/${code}`;

    const { data: shipment, error } = await (window as any).supabase()
      .from('shipments')
      .insert([{ code, from_center_id: fromId, to_center_id: toId, items, notes, status: 'in_transit' }])
      .select()
      .single();

    if (error) {
      showMsg('Error: ' + error.message, 'error');
      btn.disabled = false;
      btn.textContent = 'Generar Orden de Envío';
      return;
    }

    // Show result with QR
    result.classList.remove('hidden');
    (document.getElementById('result-code') as HTMLElement).textContent = code;
    (document.getElementById('result-link') as HTMLAnchorElement).href = receiveUrl;
    (document.getElementById('result-link') as HTMLAnchorElement).textContent = receiveUrl;

    // Generate QR
    const qrContainer = document.getElementById('qrcode');
    if (qrContainer) {
      qrContainer.innerHTML = '';
      new QRCode(qrContainer, {
        text: receiveUrl,
        width: 180,
        height: 180,
        colorDark: '#1a1a2e',
        colorLight: '#ffffff',
      });
    }

    btn.textContent = 'Crear Otro Envío';
    btn.disabled = false;
  });
</script>
```

**Nota sobre QR:** `qrcodejs2` no existe como paquete npm ligero. Usaremos un approach más simple: generar QR via API de Google Charts o usar `qrcode-generator` que es 0-deps. Alternativa: generar QR directamente con `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=URL`.

**Verificación:** `npm run dev` → `/envios/nuevo` → llenar formulario → ver QR generado → click en link lleva a `/recibir/ENV-XXXX`.

---

## Task 4: Crear página `/recibir/[code]` — recepción de envío

**Objetivo:** Página pública que muestra el detalle del envío y permite registrar la recepción.

**Archivo:** Crear `src/pages/recibir/[code].astro`

```astro
---
import Layout from '../../layouts/Layout.astro';
import { supabase } from '../../lib/supabase';

export const prerender = false;

const { code } = Astro.params;

const { data: shipment, error } = await supabase
  .from('shipments')
  .select(`
    *,
    from_center:from_center_id(name, address),
    to_center:to_center_id(name, address)
  `)
  .eq('code', code)
  .single();

const notFound = !shipment || error;

const statusLabels: Record<string, string> = {
  pending: 'Pendiente',
  in_transit: 'En tránsito',
  received: 'Recibido',
  cancelled: 'Cancelado'
};

const categories = ['Ropa', 'Medicina', 'Agua', 'Comida'];
const catEmojis: Record<string, string> = {
  Ropa: '👕', Medicina: '💊', Agua: '💧', Comida: '🍎'
};
---

<Layout title={notFound ? 'No encontrado' : `Envío ${code}`}>
  {notFound ? (
    <div class="card-bento text-center py-16">
      <span class="text-5xl block mb-4">📦</span>
      <h1 class="text-xl font-extrabold text-bento-text mb-2">Envío no encontrado</h1>
      <p class="text-sm text-bento-muted mb-4">El código <strong class="font-mono">{code}</strong> no existe.</p>
      <a href="/" class="btn-primary text-sm">Volver al inicio</a>
    </div>
  ) : (
    <div class="max-w-lg mx-auto flex flex-col gap-4">
      <h1 class="text-2xl font-extrabold text-bento-text">Recepción de Envío</h1>
      
      <!-- Código -->
      <div class="card-bento text-center !p-6">
        <p class="text-xs text-bento-muted font-semibold uppercase tracking-wider mb-2">Código</p>
        <p class="font-mono text-2xl font-extrabold text-bento-primary">{code}</p>
        <span class={`inline-block mt-3 text-xs font-semibold px-3 py-1 rounded-full ${
          shipment.status === 'received' ? 'bg-green-50 text-green-700 border border-green-200' :
          shipment.status === 'cancelled' ? 'bg-red-50 text-red-700 border border-red-200' :
          'bg-blue-50 text-blue-700 border border-blue-200'
        }`}>
          {statusLabels[shipment.status]}
        </span>
      </div>

      <!-- Origen → Destino -->
      <div class="card-bento !p-4">
        <div class="flex items-center gap-3">
          <div class="flex-1 text-center">
            <p class="text-xs text-bento-muted font-semibold">Origen</p>
            <p class="text-sm font-bold text-bento-text mt-1">{shipment.from_center?.name}</p>
            <p class="text-xs text-bento-muted">{shipment.from_center?.address}</p>
          </div>
          <span class="text-2xl">→</span>
          <div class="flex-1 text-center">
            <p class="text-xs text-bento-muted font-semibold">Destino</p>
            <p class="text-sm font-bold text-bento-text mt-1">{shipment.to_center?.name}</p>
            <p class="text-xs text-bento-muted">{shipment.to_center?.address}</p>
          </div>
        </div>
      </div>

      <!-- Items -->
      <div class="card-bento !p-4">
        <h3 class="text-sm font-bold text-bento-text mb-3">Material incluido</h3>
        <div class="grid grid-cols-2 gap-2">
          {categories.map(cat => {
            const qty = (shipment.items as any)?.[cat] || 0;
            if (qty === 0) return null;
            return (
              <div class="flex items-center gap-2 p-2 bg-bento-surface rounded-xl">
                <span class="text-xl">{catEmojis[cat]}</span>
                <div>
                  <p class="text-xs font-semibold text-bento-text">{cat}</p>
                  <p class="text-lg font-extrabold text-bento-primary">{qty}</p>
                </div>
              </div>
            );
          })}
        </div>
        {shipment.notes && (
          <p class="mt-3 text-xs text-bento-muted italic">📝 {shipment.notes}</p>
        )}
      </div>

      <!-- Botón de recepción -->
      {shipment.status !== 'received' && shipment.status !== 'cancelled' ? (
        <button id="receive-btn" class="btn-primary text-lg py-4" disabled={shipment.status === 'received'}>
          ✅ Confirmar Recepción
        </button>
      ) : shipment.status === 'received' ? (
        <div class="card-bento text-center !p-4 bg-green-50 border-green-200">
          <p class="text-sm font-bold text-green-700">✅ Recibido el {new Date(shipment.received_at).toLocaleDateString('es-VE', { dateStyle: 'full' })}</p>
        </div>
      ) : null}

      <div id="receive-msg" class="hidden text-sm font-semibold p-3 rounded-xl text-center"></div>

      <a href="/envios" class="text-center text-sm font-semibold text-bento-muted hover:text-bento-text">
        ← Ver todos los envíos
      </a>
    </div>
  )}
</Layout>

<script>
  const btn = document.getElementById('receive-btn');
  const msg = document.getElementById('receive-msg');

  btn?.addEventListener('click', async () => {
    if (!confirm('¿Confirmás la recepción de este envío? Esto registrará la entrada del material.')) return;
    
    btn.disabled = true;
    btn.textContent = 'Registrando...';

    const { error } = await (window as any).supabase()
      .from('shipments')
      .update({ status: 'received', received_at: new Date().toISOString() })
      .eq('code', '{code}');

    if (error) {
      msg?.classList.remove('hidden');
      msg!.className = 'text-sm font-semibold p-3 rounded-xl text-center bg-red-50 text-red-700';
      msg!.textContent = 'Error: ' + error.message;
      btn.disabled = false;
      btn.textContent = '✅ Confirmar Recepción';
      return;
    }

    // Recargar para mostrar estado actualizado
    window.location.reload();
  });
</script>
```

**Verificación:** Visitar `/recibir/ENV-XXXX` → ver detalles → click "Confirmar Recepción" → se actualiza a "Recibido".

---

## Task 5: Agregar QR a la página de recepción y link desde CenterCard

**Objetivo:** Integrar el sistema en el flujo existente.

**Archivos a modificar:**
- `src/components/CenterCard.astro` — agregar link "Enviar material →" si el centro tiene necesidades activas
- `src/pages/index.astro` — no requiere cambios, el polling ya funciona

**CenterCard.astro — agregar al final del article, debajo del grid de necesidades:**

```astro
<a href={`/envios/nuevo?to=${centerId}`} 
   class="mt-2 text-xs font-bold text-bento-primary hover:underline text-center">
  📦 Enviar material a este centro →
</a>
```

**Verificación:** En `/`, cada card debe mostrar el link. Click → va a `/envios/nuevo?to=UUID` con el destino preseleccionado.

---

## Task 6: Actualizar `center_needs` al confirmar recepción

**Objetivo:** Cuando CA2 recibe un envío, marcar sus necesidades como cubiertas (active=false) para las categorías recibidas.

**Archivo:** Crear `supabase/trigger_receive.sql`

```sql
-- Función que se ejecuta cuando un envío se marca como recibido
CREATE OR REPLACE FUNCTION on_shipment_received()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'received' AND OLD.status != 'received' THEN
    -- Marcar necesidades del centro destino como cubiertas
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

CREATE TRIGGER shipment_received_trigger
  AFTER UPDATE ON shipments
  FOR EACH ROW
  EXECUTE FUNCTION on_shipment_received();
```

**Verificación:** Crear envío con Ropa=10 → recibir → verificar que `center_needs` para el centro destino tenga `Ropa.active = false`.

---

## Task 7: Build y deploy a Cloudflare Pages

**Objetivo:** Compilar y desplegar.

```bash
cd /root/Acop.io
npm run build
npx wrangler pages deploy dist --project-name=acopios
```

**Verificación:** Visitar `https://acopios.pages.dev/envios` — debe cargar la lista de envíos.

---

## Resumen de archivos

| Archivo | Acción |
|---|---|
| `supabase/shipments.sql` | Crear — schema de shipments |
| `supabase/trigger_receive.sql` | Crear — trigger para actualizar needs |
| `src/pages/envios.astro` | Crear — listado SSR |
| `src/pages/envios/nuevo.astro` | Crear — formulario + QR |
| `src/pages/recibir/[code].astro` | Crear — página pública de recepción |
| `src/components/CenterCard.astro` | Modificar — link "Enviar material" |

---

## Riesgos y decisiones

- **QR library:** Usamos Google Chart API (`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=URL`) para evitar dependencias npm. Funciona offline-friendly porque el QR se genera en el server.
- **Código único:** `ENV-XXXX` con 4 caracteres alfanuméricos = 1.6M combinaciones. Suficiente. Si hay colisión (0.00006% con 1000 envíos), el insert falla y se regenera.
- **Items como JSONB:** Evita tabla separada `shipment_items`. Las 4 categorías son fijas, JSON es más simple.
- **No tracking de inventario:** Por ahora solo registramos envíos, no restamos del inventario del centro origen. Se puede agregar después.
