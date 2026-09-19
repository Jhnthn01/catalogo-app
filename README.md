# 📦 Catálogo Digital & ERP Ferretería PRO

Sistema integral de gestión de catálogo, inventario, abastecimiento y punto de venta desarrollado en **Flutter** con backend en la nube en **Supabase** (PostgreSQL).

Diseñado para operar en entornos **Web, Desktop y Móvil** con soporte multi-tienda y control de acceso basado en roles (RBAC).

---

## 🚀 Características Principales

### 🛒 1. Catálogo Digital y Punto de Venta
- **Buscador Inteligente Multi-Token:** Búsqueda flexible por múltiples palabras clave con soporte para operadores lógicos (`Cualquiera / OR` o `Todas / AND`).
- **Filtrado Jerárquico:** Filtros dinámicos por Categoría, Clase y Sub-clase.
- **Ficha de Producto:** Control detallado de SKU, UPC, ALU, marca, color, descripción técnica, costo, precio de venta, último costo de compra con fecha y costo medio variable (PMP).
- **Gestión de Carrito y Reservas:** Control de stock físico y soporte para pedidos en tienda o sobreventa controlada.

### 📊 2. Inventario y Control de Stock
- **Tabla Detallada de Inventario:** Vista general con KPIs de valorización total del stock, cantidades globales, márgenes comerciales calculados y auditoría de últimas modificaciones.
- **Kardex Físico y Valorizado:** Trazabilidad completa de movimientos de entrada, salida, ajustes y transferencias entre tiendas.
- **Carga Masiva (CSV):** Importación y actualización de catálogo y stocks de manera masiva.
- **Validación de Ajustes:** Flujo de auditoría donde los almacenistas reportan diferencias físicas y los gerentes/administradores validan o rechazan los ajustes.

### 🚚 3. Abastecimiento y Proveedores
- **Órdenes de Compra:** Generación y seguimiento de órdenes a proveedores.
- **Recepción de Mercancía:** Recepción física parcial o total con recálculo automatizado de:
  - **Último Costo de Compra** y su **Fecha de Registro**.
  - **Costo Medio Ponderado (PMP)** en tiempo real.
- **Gestión de Proveedores:** Directorio con RUC, Razón Social, teléfono, correo y contacto.

### 📋 4. Pedidos y Despachos
- **Estados de Pedido:** Gestión de ciclo de vida (Pendientes, Entregados, Cancelados).
- **Generación de Comprobantes (PDF):** Impresión directa y exportación a PDF con código QR de verificación e información detallada de items.
- **Alertas en Tiempo Real:** Notificaciones visuales y badges reactivos de pedidos pendientes según la tienda seleccionada.

### 🔐 5. Seguridad y Multi-Tienda
- **Control de Acceso Basado en Roles (RBAC):** Perfiles para Administrador, Gerente, Almacenista, Cajero y Vendedor.
- **Multi-Sucursal:** Selector dinámico de tienda con aislamiento de inventario y stock consolidado.
- **Actualizador Integrado:** Verificación automática de nuevas versiones para despliegues continuos.

---

## 🛠️ Tecnologías Utilizadas

- **Frontend:** [Flutter](https://flutter.dev/) (Dart 3.x)
- **Backend & Base de Datos:** [Supabase](https://supabase.com/) (PostgreSQL)
- **Autenticación:** Supabase Auth con gestión de sesiones persistentes y recuperación de contraseñas.
- **Generación de Reportes:** `pdf`, `printing` y `qr_flutter`.
- **Escaner de Códigos:** `mobile_scanner`.

---

## 📂 Estructura del Proyecto

```text
lib/
├── app.dart                                # Configuración de temas, rutas y observadores
├── main.dart                               # Punto de entrada e inicialización de Supabase
├── core/                                   # Constantes, temas y utilidades del sistema
├── data/
│   └── models/                             # Modelos de datos (ProductoModel, KardexModel, etc.)
├── features/
│   ├── abastecimiento/                     # Órdenes de compra, recepción y proveedores
│   ├── admin/                              # Gestión de usuarios y roles
│   ├── auth/                               # Login, registro y recuperación de contraseña
│   ├── cart/                               # Carrito de compras y checkout
│   ├── catalog/                            # Catálogo digital y gestión de ficha de producto
│   ├── inventory/                          # Tabla detallada, Kardex, carga masiva y ajustes
│   ├── orders/                             # Pedidos pendientes, entregados, cancelados y PDF
│   └── profile/                            # Perfil de usuario y cuenta
├── services/                               # Servicios de conexión a Supabase y lógica de negocio
└── widgets/                                # Componentes UI reutilizables (Buscador, Menú, etc.)
```

---

## ⚙️ Instalación y Configuración

### 1. Prerrequisitos
- Flutter SDK instalado (`>= 3.11.4`).
- Cuenta y proyecto en [Supabase](https://supabase.com/).

### 2. Clonar el Repositorio
```bash
git clone https://github.com/Jhnthn01/catalogo-app.git
cd catalogo-app
```

### 3. Instalar Dependencias
```bash
flutter pub get
```

### 4. Configurar Base de Datos (Supabase)
Ejecuta los scripts ubicados en la carpeta `sql/` dentro del **SQL Editor** de Supabase para inicializar las funciones RPC y tablas:
- `sql/buscar_productos.sql` (Buscador avanzado multi-token y compatibilidad de tipos UUID).

### 5. Ejecutar la Aplicación
```bash
# Para entorno Web
flutter run -d chrome

# Para Windows Desktop
flutter run -d windows

# Para Móvil (Android/iOS)
flutter run
```

---

## 📄 Licencia

Este proyecto está desarrollado para uso empresarial privado. Todos los derechos reservados.
