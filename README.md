# GastroApp - MVP Gestión Gastronómica

Prototipo funcional de una aplicación web para gestión gastronómica básica.

## Tecnologías

- **C# / ASP.NET Core 7.0**
- **Blazor Server**
- **Persistencia en memoria** (sin base de datos)

## Estructura del Proyecto

```
GastroApp/
├── Models/                 # Modelos de datos
│   ├── Product.cs         # Productos con indicador de margen
│   ├── Sale.cs            # Ventas y items de venta
│   ├── CashRegister.cs    # Caja diaria
│   └── DailySummary.cs    # Resumen del día
├── Services/              # Lógica de negocio
│   ├── DataStorageService.cs      # Almacenamiento en memoria
│   ├── ProductService.cs          # Gestión de productos
│   ├── SaleService.cs             # Gestión de ventas
│   └── CashRegisterService.cs     # Gestión de caja
└── Pages/                 # Páginas Blazor
    ├── Index.razor        # Home
    ├── Products.razor     # Gestión de productos
    ├── Sales.razor        # Punto de venta
    ├── Cash.razor         # Caja diaria
    └── Summary.razor      # Resumen del día
```

## Funcionalidades

### 1. Productos
- Crear, editar y listar productos
- Campos: Nombre, Precio, Costo (opcional)
- Indicador visual de margen:
  - 🟢 Verde: margen saludable (30%+)
  - 🟠 Amarillo: margen bajo (0-30%)
  - 🔴 Rojo: pérdida (negativo)

### 2. Punto de Venta
- Pantalla tipo mostrador
- Click en producto para agregar al carrito
- Visualización del total
- Botón "Cobrar" para registrar venta
- Requiere caja abierta

### 3. Caja Diaria
- Abrir caja con monto inicial
- Ver ventas del día en tiempo real
- Cerrar caja ingresando monto final
- Cálculo automático de diferencia
- Solo una caja por día

### 4. Resumen Diario
- Total vendido
- Cantidad de ventas
- Producto más vendido
- Estado de caja (diferencia)

## Cómo Ejecutar

```bash
cd GastroApp
dotnet run
```

La aplicación estará disponible en: **http://localhost:5258**

Para detener: presionar `Ctrl+C`

## Flujo de Uso Recomendado

1. **Abrir Caja** (menú Caja)
   - Ingresar monto inicial
   - Click en "Abrir Caja"

2. **Gestionar Productos** (menú Productos)
   - Crear productos con precio y costo
   - Verificar indicador de margen

3. **Realizar Ventas** (menú Vender)
   - Click en productos para agregar al carrito
   - Click en "Cobrar" para completar venta

4. **Cerrar Caja** (menú Caja)
   - Contar efectivo
   - Ingresar monto final
   - Ver diferencia automática

5. **Ver Resumen** (menú Resumen)
   - Revisar estadísticas del día
   - Ver producto más vendido

## Notas Técnicas

- **Persistencia:** Todos los datos se mantienen en memoria. Al reiniciar la aplicación se pierden los datos.
- **Datos de ejemplo:** La app incluye 3 productos pre-cargados para probar.
- **Sin autenticación:** No hay login ni usuarios.
- **Un solo dispositivo:** Pensado para uso local.
- **Arquitectura simple:** Sin patrones enterprise, sin CQRS, sin DDD.

## Próximas Mejoras Posibles

- Persistencia en archivo JSON
- Historial de ventas
- Reportes por rango de fechas
- Categorías de productos
- Impresión de tickets
- Gestión de stock

---

**MVP creado para prototipado rápido. No apto para producción.**
