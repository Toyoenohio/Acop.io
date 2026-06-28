# Acop.io 📦

Acop.io es una plataforma web desarrollada para gestionar y visibilizar en tiempo real el estado de los centros de acopio (especialmente enfocada en el estado Anzoátegui, Venezuela, pero adaptable a cualquier región). Permite a los donantes conocer exactamente qué insumos se necesitan (Agua, Comida, Medicina, Ropa) y cuáles centros ya están a su máxima capacidad.

## 🚀 Características Principales

*   **Vista Pública en Tiempo Real:** Los donantes pueden ver una lista de centros de acopio y sus necesidades actualizadas al instante (SSR).
*   **Diseño "Mobile-First":** Interfaz optimizada para teléfonos móviles utilizando el Sistema de Diseño Bento (esquinas redondeadas suaves, colores cálidos, accesibilidad con emojis).
*   **Sistema de Roles:**
    *   **Donantes (Público):** Visualizan la información.
    *   **Gestores:** Tienen acceso a un `/dashboard` privado donde con un solo toque cambian el estado de las categorías de su centro (`✓ Activo` o `✗ Lleno`).
    *   **Súper Administrador:** Tiene acceso al `/admin` para registrar nuevos centros de acopio en la base de datos.
*   **Autenticación Segura:** Protegido con Supabase Auth y Row Level Security (RLS) en la base de datos.

## 🛠️ Stack Tecnológico

*   **Framework:** [Astro](https://astro.build/) (SSR con adaptador de Cloudflare)
*   **Estilos:** [Tailwind CSS](https://tailwindcss.com/) (Vanilla CSS tokens)
*   **Base de Datos y Auth:** [Supabase](https://supabase.com/) (PostgreSQL)
*   **Despliegue:** Cloudflare Pages

## 📦 Estructura del Proyecto

```text
/
├── public/                 # Archivos estáticos (favicon, imágenes)
├── src/
│   ├── components/         # Componentes UI (CenterCard, CategoryIcon)
│   ├── layouts/            # Layout principal (Layout.astro)
│   ├── lib/                # Utilidades y configuración (supabase.ts)
│   ├── pages/              # Rutas de la app (index, login, admin, dashboard)
│   └── styles/             # Estilos globales y tokens (global.css)
├── supabase/               # Scripts SQL para la BD (schema.sql, trigger.sql, fix_rls.sql)
└── astro.config.mjs        # Configuración de Astro y adaptadores
```

## ⚙️ Configuración y Desarrollo Local

### 1. Clonar el repositorio
```bash
git clone https://github.com/Toyoenohio/Acop.io.git
cd Acop.io
```

### 2. Instalar dependencias
```bash
npm install
```

### 3. Configurar variables de entorno
Crea un archivo `.env` en la raíz del proyecto basado en las credenciales de tu proyecto de Supabase:
```env
PUBLIC_SUPABASE_URL=tu_supabase_url
PUBLIC_SUPABASE_ANON_KEY=tu_supabase_anon_key
```

### 4. Configurar Base de Datos
Debes ejecutar los scripts SQL ubicados en la carpeta `supabase/` en el **SQL Editor** de tu proyecto en Supabase:
1. `schema.sql`: Crea las tablas, tipos y políticas RLS básicas.
2. `trigger.sql`: Crea el automatismo para que los nuevos usuarios sean `manager` por defecto.
3. `fix_rls.sql`: Aplica un parche de seguridad para evitar errores de recursión infinita en Postgres.

Para asignarte como administrador por primera vez, ejecuta:
```sql
INSERT INTO public.profiles (id, role)
SELECT id, 'super_admin' FROM auth.users LIMIT 1;
```

### 5. Iniciar servidor de desarrollo
```bash
npm run dev
```
La aplicación estará disponible en `http://localhost:4321`.

## 📄 Licencia

Este proyecto es de código abierto.
