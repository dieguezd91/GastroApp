# 🍽️ GastroApp - Nuevas Funcionalidades

## 📦 Módulos Implementados

### 1. 🥕 Ingredientes
Gestión de materia prima con control de stock.

**Características:**
- CRUD completo de ingredientes
- Unidades de medida: kg, lt, unidad, gr, ml
- Estado activo/inactivo
- Último precio conocido (desde facturas)

**Ruta:** `/ingredients`

---

### 2. 🚚 Proveedores
Registro simple de proveedores.

**Características:**
- CRUD completo de proveedores
- Información básica (nombre)

**Ruta:** `/suppliers`

---

### 3. 📄 Facturas de Proveedores
Historial de compras con precios.

**Características:**
- Crear facturas con múltiples items
- Cada item asocia ingrediente + cantidad + precio unitario
- Número de factura opcional
- Notas adicionales
- Cálculo automático de totales
- Ordenadas por fecha (más reciente primero)

**Ruta:** `/invoices`

**Flujo de uso:**
1. Crear nueva factura
2. Seleccionar proveedor y fecha
3. Agregar items (ingrediente + cantidad + precio)
4. Guardar factura

---

### 4. 📖 Recetas Estandarizadas
Costeo automático de recetas.

**Características:**
- CRUD completo de recetas
- Agregar ingredientes con cantidades
- Definir rendimiento (porciones/pax)
- **Cálculo automático de costos:**
  - Usa el último precio cargado en facturas
  - Calcula costo total de la receta
  - Calcula costo por porción
- **Indicadores visuales de costo:**
  - 🟢 Verde: Costo normal (< $100 por porción)
  - 🟡 Amarillo: Costo elevado ($100-$200 por porción)
  - 🔴 Rojo: Costo crítico (> $200 por porción)
- Botón de recalcular costos (🔄) para actualizar precios

**Ruta:** `/recipes`

**Flujo de uso:**
1. Crear nueva receta
2. Definir nombre y rendimiento
3. Agregar ingredientes (muestra precio actual)
4. Ver preview del costo en tiempo real
5. Guardar receta

---

## 🔄 Integración con Sistema Existente

### Persistencia
- Todo se guarda en `data.json`
- Carga automática al iniciar
- Sin base de datos externa

### Autenticación
- Solo accesible para usuarios Admin
- Empleados NO ven estos módulos
- Reutiliza el sistema de auth existente

### Navegación
Nuevo menú lateral para Admin:
- Home
- **Productos** (existente)
- **Ingredientes** ✨ NUEVO
- **Recetas** ✨ NUEVO
- **Proveedores** ✨ NUEVO
- **Facturas** ✨ NUEVO
- Vender
- Caja
- Resumen

---

## 🎯 Casos de Uso

### Caso 1: Cargar Ingredientes y Precios
1. Ir a **Ingredientes** → Crear ingredientes básicos
2. Ir a **Proveedores** → Crear proveedor
3. Ir a **Facturas** → Crear factura con items
4. Los precios quedan registrados

### Caso 2: Crear Receta con Costo
1. Asegurar que existan ingredientes con precios
2. Ir a **Recetas** → Crear receta
3. Agregar ingredientes y cantidades
4. El sistema calcula automáticamente el costo
5. Ver indicador de costo (🟢🟡🔴)

### Caso 3: Actualizar Precios
1. Ir a **Facturas** → Crear nueva factura con precios actualizados
2. Ir a **Recetas** → Hacer clic en 🔄 para recalcular
3. Ver los nuevos costos actualizados

### Caso 4: Análisis de Rentabilidad
1. Ver costo unitario de receta en **Recetas**
2. Comparar con precio de venta del producto final
3. Determinar margen de ganancia

---

## 💡 Decisiones de Diseño

### ✅ Simplicidad
- Sin abstracciones complejas
- Servicios CRUD directos
- Sin repositorios ni UoW
- Sin caché

### ✅ Cálculo de Costos
**Lógica implementada:**
```
Último precio ingrediente = último InvoiceItem (por fecha)
Costo receta = suma(cantidad × último precio)
Costo unitario = costo total ÷ rendimiento
```

**Indicadores visuales:**
- Basados en umbrales fijos de costo unitario
- Verde: < $100
- Amarillo: $100-$200
- Rojo: > $200

### ✅ Desnormalización
- `IngredientName` repetido en InvoiceItem y RecipeIngredient
- Facilita el display sin joins
- Mantiene historial aunque se edite el ingrediente

### ✅ Sin Validaciones Complejas
- Validaciones mínimas en UI
- Sin reglas de negocio complicadas
- Prioridad en funcionalidad sobre perfección

---

## 🚀 Cómo Probar

### 1. Iniciar la aplicación
```bash
cd Desktop/GastroApp/GastroApp
dotnet run
```

### 2. Login
- Usuario: `admin`
- Contraseña: `admin`

### 3. Ver datos de ejemplo
El sistema viene con seed data:
- 4 ingredientes (Harina, Leche, Huevos, Manteca)
- 1 proveedor (Distribuidora San Martín)
- 1 factura con precios
- 1 receta de ejemplo (Medialunas Caseras)

### 4. Probar funcionalidades
- **Ingredientes:** Ver lista, crear nuevos, editar
- **Proveedores:** Ver lista, crear nuevos
- **Facturas:** Ver existente, crear nueva con items
- **Recetas:** Ver "Medialunas Caseras", verificar cálculo de costos

---

## 📊 Estructura de Archivos Nuevos

```
Models/
  ├── Ingredient.cs
  ├── Supplier.cs
  ├── Invoice.cs
  ├── InvoiceItem.cs
  ├── Recipe.cs
  └── RecipeIngredient.cs

Services/
  ├── IngredientService.cs
  ├── SupplierService.cs
  ├── InvoiceService.cs
  └── RecipeService.cs

Pages/
  ├── Ingredients.razor
  ├── Suppliers.razor
  ├── Invoices.razor
  └── Recipes.razor
```

**Archivos modificados:**
- `Services/DataStorageService.cs` - Agregadas nuevas listas y persistencia
- `Program.cs` - Registrados nuevos servicios
- `Shared/NavMenu.razor` - Agregados links de navegación

---

## 🔮 Mejoras Futuras Sugeridas

1. **Historial de cambios de precios:**
   - Gráfico de evolución de precios por ingrediente
   - Comparación temporal de costos de recetas

2. **Análisis de rentabilidad:**
   - Comparar costo de receta vs precio de producto
   - Alertas de margen bajo

3. **Batch updates:**
   - Recalcular todas las recetas de una vez
   - Actualización masiva de precios

4. **Unidades de conversión:**
   - Convertir kg a gr automáticamente
   - Manejar fracciones comunes

5. **Exportación:**
   - Exportar recetas a PDF
   - Listado de compras sugerido

---

## ⚠️ Limitaciones Conocidas

1. **Sin conversión de unidades:**
   - Si una factura tiene "gr" y la receta usa "kg", hay que convertir manualmente

2. **Último precio siempre:**
   - No hay promedios ni ponderaciones
   - Siempre toma el precio más reciente

3. **Sin validación de stock:**
   - No controla si hay suficiente ingrediente
   - Es solo para costeo, no inventario

4. **Indicadores fijos:**
   - Los umbrales de 🟢🟡🔴 son arbitrarios
   - Podrían ser configurables en el futuro

5. **Sin auditoría:**
   - No registra quién modificó qué
   - No hay historial de cambios en recetas

---

## ✅ Testing Manual

### Checklist de Funcionalidades

**Ingredientes:**
- [ ] Crear ingrediente
- [ ] Editar ingrediente
- [ ] Activar/desactivar ingrediente
- [ ] Ver último precio en lista

**Proveedores:**
- [ ] Crear proveedor
- [ ] Editar proveedor
- [ ] Eliminar proveedor

**Facturas:**
- [ ] Crear factura
- [ ] Agregar múltiples items
- [ ] Ver total calculado
- [ ] Ver lista de facturas ordenadas
- [ ] Eliminar factura

**Recetas:**
- [ ] Crear receta
- [ ] Agregar ingredientes
- [ ] Ver preview de costo en tiempo real
- [ ] Guardar receta
- [ ] Ver indicador de costo (🟢🟡🔴)
- [ ] Recalcular costos (botón 🔄)
- [ ] Ver desglose de ingredientes (details)
- [ ] Editar receta existente

**Integración:**
- [ ] Los precios de facturas se reflejan en ingredientes
- [ ] Los precios de ingredientes se usan en recetas
- [ ] Todo persiste en data.json
- [ ] Todo se carga correctamente al reiniciar

---

## 🎓 Notas Técnicas

### Orden de Registro de Servicios
Importante: `InvoiceService` debe registrarse ANTES que `IngredientService` y `RecipeService` porque estos últimos dependen de él.

### Cálculo en Tiempo Real
Las recetas muestran un preview del costo mientras se editan, actualizando en cada cambio.

### JSON Serialization
Los modelos con propiedades calculadas (como `Total` en Invoice) se serializan correctamente porque son getters simples.

---

## 📝 Supuestos Importantes

1. **Un solo precio por ingrediente:**
   - Se usa el último precio cargado
   - No se manejan precios por proveedor

2. **Recetas inmutables en historial:**
   - Una vez guardada, una receta refleja los precios del momento
   - Al recalcular, se actualizan con precios actuales

3. **Sin control de acceso granular:**
   - Todo Admin puede ver/editar todo
   - Empleados no ven nada de este módulo

4. **Persistencia simple:**
   - JSON en disco
   - Sin transacciones
   - Sin rollback

---

Implementado con ❤️ siguiendo el estilo simple y directo del prototipo existente.
