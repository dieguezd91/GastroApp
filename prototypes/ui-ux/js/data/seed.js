export const PAYMENT_METHODS = [
  { id: 'Cash', label: 'Efectivo', short: 'Efectivo' },
  { id: 'DebitCard', label: 'Tarjeta de débito', short: 'Débito' },
  { id: 'CreditCard', label: 'Tarjeta de crédito', short: 'Crédito' },
  { id: 'Transfer', label: 'Transferencia', short: 'Transferencia' },
  { id: 'MercadoPago', label: 'Mercado Pago', short: 'Mercado Pago' },
  { id: 'Other', label: 'Otro', short: 'Otro' },
];

export const PAYMENT_METHOD_MAP = Object.fromEntries(PAYMENT_METHODS.map((m) => [m.id, m]));

export const UNITS = ['kg', 'gr', 'lt', 'ml', 'unidad'];

export const WASTE_CATEGORIES = [
  { id: 'Vencimiento', label: 'Vencimiento' },
  { id: 'RoturaODerrame', label: 'Rotura o derrame' },
  { id: 'ErrorDePreparacion', label: 'Error de preparación' },
  { id: 'Otro', label: 'Otro' },
];

export const STOCK_MOVEMENT_LABELS = {
  InvoiceReceipt: 'Ingreso por compra',
  SaleConsumption: 'Consumo por venta',
  SaleCancellationReturn: 'Reposición por anulación',
  RefundReturn: 'Reposición por devolución',
  Adjustment: 'Ajuste manual',
  Waste: 'Merma',
  CountAdjustment: 'Ajuste por conteo',
  InitialStock: 'Stock inicial',
};

export const CASH_MOVEMENT_LABELS = {
  Sale: 'Venta (efectivo)',
  Income: 'Ingreso',
  Expense: 'Gasto',
  Withdrawal: 'Retiro',
  Refund: 'Devolución (efectivo)',
};

export const AR_DENOMINATIONS = [20000, 10000, 2000, 1000, 500, 200, 100];

export function createInitialData() {
  const users = [
    { id: 1, username: 'admin', fullName: 'Camila Ríos', role: 'Admin', initials: 'CR', active: true },
    { id: 2, username: 'empleado', fullName: 'Lucas Méndez', role: 'Employee', initials: 'LM', active: true },
    { id: 3, username: 'sofia', fullName: 'Sofía Pereyra', role: 'Employee', initials: 'SP', active: true },
  ];

  const categories = [
    { id: 1, name: 'Cafetería' },
    { id: 2, name: 'Panadería y Pastelería' },
    { id: 3, name: 'Cocina' },
    { id: 4, name: 'Bebidas' },
  ];

  const products = [
    { id: 1, name: 'Café con leche', price: 4200, cost: 1180, categoryId: 1, isActive: true },
    { id: 2, name: 'Flat White', price: 4600, cost: 1320, categoryId: 1, isActive: true },
    { id: 3, name: 'Medialunas de manteca (x2)', price: 3200, cost: 980, categoryId: 2, isActive: true },
    { id: 4, name: 'Tostado de jamón y queso', price: 6800, cost: 5130, categoryId: 3, isActive: true },
    { id: 5, name: 'Hamburguesa Clásica', price: 13900, cost: 5890, categoryId: 3, isActive: true },
    { id: 6, name: 'Milanesa Napolitana con fritas', price: 16500, cost: 11850, categoryId: 3, isActive: true },
    { id: 7, name: 'Empanadas de carne (x3)', price: 7500, cost: 2650, categoryId: 3, isActive: true },
    { id: 8, name: 'Limonada con menta y jengibre', price: 4500, cost: 920, categoryId: 4, isActive: true },
    { id: 9, name: 'Agua sin gas 500 ml', price: 2600, cost: 850, categoryId: 4, isActive: true },
    { id: 10, name: 'Brownie tibio con helado', price: 6200, cost: 2150, categoryId: 2, isActive: true },
    { id: 11, name: 'Pan de campo artesanal', price: 4900, cost: 1600, categoryId: null, isActive: true },
    { id: 12, name: 'Tarta de calabaza y brie', price: 9400, cost: 4100, categoryId: 3, isActive: false },
  ];

  const ingredients = [
    { id: 1, name: 'Café en grano', unit: 'kg', currentStock: 4.2, minStock: 2.0, active: true, dailyUsage7d: 0.75, lastUnitPrice: 36000 },
    { id: 2, name: 'Leche entera', unit: 'lt', currentStock: 3.5, minStock: 5.0, active: true, dailyUsage7d: 2.0, lastUnitPrice: 1750 },
    { id: 3, name: 'Pan brioche', unit: 'unidad', currentStock: 2, minStock: 12, active: true, dailyUsage7d: 8.5, lastUnitPrice: 950 },
    { id: 4, name: 'Carne picada especial', unit: 'kg', currentStock: 6.4, minStock: 3.0, active: true, dailyUsage7d: 2.1, lastUnitPrice: 11800 },
    { id: 5, name: 'Queso cheddar', unit: 'kg', currentStock: 0.6, minStock: 1.5, active: true, dailyUsage7d: 0.45, lastUnitPrice: 16400 },
    { id: 6, name: 'Limón', unit: 'kg', currentStock: 0, minStock: 2.5, active: true, dailyUsage7d: 0.9, lastUnitPrice: 2800 },
    { id: 7, name: 'Jamón cocido natural', unit: 'kg', currentStock: 1.8, minStock: 1.2, active: true, dailyUsage7d: 0.5, lastUnitPrice: 19200 },
    { id: 8, name: 'Queso tybo barra', unit: 'kg', currentStock: 2.4, minStock: 1.5, active: true, dailyUsage7d: 0.6, lastUnitPrice: 14900 },
    { id: 9, name: 'Nalga para milanesa', unit: 'kg', currentStock: 3.8, minStock: 2.5, active: true, dailyUsage7d: 1.4, lastUnitPrice: 15800 },
    { id: 10, name: 'Papas bastón congeladas', unit: 'kg', currentStock: 11.0, minStock: 5.0, active: true, dailyUsage7d: 3.2, lastUnitPrice: 3900 },
  ];

  // Recipes matched by exact Product.Name == Recipe.Name (current GastroApp contract)
  const recipes = [
    {
      id: 1,
      name: 'Café con leche',
      yield: 1,
      lastCalculatedCost: 1150,
      lastCalculatedAt: '2026-11-20T09:10:00-03:00',
      ingredients: [
        { ingredientId: 1, quantity: 18, unit: 'gr' },
        { ingredientId: 2, quantity: 220, unit: 'ml' },
      ],
    },
    {
      id: 2,
      name: 'Flat White',
      yield: 1,
      lastCalculatedCost: 1290,
      lastCalculatedAt: '2026-11-20T09:10:00-03:00',
      ingredients: [
        { ingredientId: 1, quantity: 20, unit: 'gr' },
        { ingredientId: 2, quantity: 180, unit: 'ml' },
      ],
    },
    {
      id: 3,
      name: 'Hamburguesa Clásica',
      yield: 1,
      lastCalculatedCost: 3450,
      lastCalculatedAt: '2026-11-18T11:00:00-03:00',
      ingredients: [
        { ingredientId: 3, quantity: 1, unit: 'unidad' },
        { ingredientId: 4, quantity: 180, unit: 'gr' },
        { ingredientId: 5, quantity: 60, unit: 'gr' },
        { ingredientId: 10, quantity: 180, unit: 'gr' },
      ],
    },
    {
      id: 4,
      name: 'Milanesa Napolitana con fritas',
      yield: 1,
      lastCalculatedCost: 4700,
      lastCalculatedAt: '2026-11-15T10:20:00-03:00',
      ingredients: [
        { ingredientId: 9, quantity: 260, unit: 'gr' },
        { ingredientId: 7, quantity: 60, unit: 'gr' },
        { ingredientId: 8, quantity: 80, unit: 'gr' },
        { ingredientId: 10, quantity: 240, unit: 'gr' },
      ],
    },
    {
      id: 5,
      name: 'Tostado de jamón y queso',
      yield: 1,
      lastCalculatedCost: 2350,
      lastCalculatedAt: '2026-11-19T12:00:00-03:00',
      ingredients: [
        { ingredientId: 7, quantity: 70, unit: 'gr' },
        { ingredientId: 8, quantity: 80, unit: 'gr' },
      ],
    },
    {
      id: 6,
      name: 'Limonada con menta y jengibre',
      yield: 1,
      lastCalculatedCost: 520,
      lastCalculatedAt: '2026-11-19T12:00:00-03:00',
      ingredients: [
        { ingredientId: 6, quantity: 180, unit: 'gr' },
      ],
    },
  ];

  const suppliers = [
    { id: 1, name: 'Tostadores del Sur S.R.L.' },
    { id: 2, name: 'Lácteos La Pampa Distribuidora' },
    { id: 3, name: 'Frigorífico Don Ernesto' },
    { id: 4, name: 'Verdulería Mayorista Central' },
  ];

  const invoices = [
    {
      id: 204,
      date: '2026-11-21T07:50:00-03:00',
      supplierId: 3,
      invoiceNumber: 'FC-A 0004-00018291',
      notes: 'Suba de lista en nalga y carne picada (+22%).',
      items: [
        { ingredientId: 9, quantity: 5, unit: 'kg', unitPrice: 15800 },
        { ingredientId: 4, quantity: 8, unit: 'kg', unitPrice: 11800 },
      ],
    },
    {
      id: 203,
      date: '2026-11-20T08:15:00-03:00',
      supplierId: 2,
      invoiceNumber: 'FC-B 0002-00004910',
      notes: 'Entrega semanal de lácteos y fiambres.',
      items: [
        { ingredientId: 2, quantity: 12, unit: 'lt', unitPrice: 1750 },
        { ingredientId: 5, quantity: 2, unit: 'kg', unitPrice: 16400 },
        { ingredientId: 7, quantity: 3, unit: 'kg', unitPrice: 19200 },
        { ingredientId: 8, quantity: 4, unit: 'kg', unitPrice: 14900 },
      ],
    },
    {
      id: 202,
      date: '2026-11-19T09:00:00-03:00',
      supplierId: 1,
      invoiceNumber: 'FC-A 0001-00009122',
      notes: 'Blend espresso Brasil / Colombia.',
      items: [
        { ingredientId: 1, quantity: 6, unit: 'kg', unitPrice: 36000 },
      ],
    },
  ];

  const cashRegisters = [
    {
      id: 18,
      status: 'Open',
      openedAt: '2026-11-21T08:30:00-03:00',
      closedAt: null,
      openedBy: 'Camila Ríos',
      closedBy: null,
      initialAmount: 45000,
      countedAmount: null,
      expectedAmountSnapshot: null,
      differenceSnapshot: null,
      countRecord: null,
      movementVersion: 7,
    },
    {
      id: 17,
      status: 'Closed',
      openedAt: '2026-11-20T08:15:00-03:00',
      closedAt: '2026-11-20T21:40:00-03:00',
      openedBy: 'Camila Ríos',
      closedBy: 'Camila Ríos',
      initialAmount: 40000,
      countedAmount: 118500,
      expectedAmountSnapshot: 119000,
      differenceSnapshot: -500,
      countRecord: {
        denominations: [
          { value: 20000, qty: 3 },
          { value: 10000, qty: 5 },
          { value: 2000, qty: 3 },
          { value: 1000, qty: 2 },
          { value: 500, qty: 1 },
        ],
        differenceReason: 'Redondeo de cambio en turno tarde.',
        countedAt: '2026-11-20T21:40:00-03:00',
        countedBy: 'Camila Ríos',
      },
      movementVersion: 12,
    },
    {
      id: 16,
      status: 'Closed',
      openedAt: '2026-11-19T08:20:00-03:00',
      closedAt: '2026-11-19T21:30:00-03:00',
      openedBy: 'Camila Ríos',
      closedBy: 'Camila Ríos',
      initialAmount: 40000,
      countedAmount: 134200,
      expectedAmountSnapshot: 134200,
      differenceSnapshot: 0,
      countRecord: {
        denominations: [
          { value: 20000, qty: 4 },
          { value: 10000, qty: 5 },
          { value: 2000, qty: 2 },
          { value: 200, qty: 1 },
        ],
        differenceReason: '',
        countedAt: '2026-11-19T21:30:00-03:00',
        countedBy: 'Camila Ríos',
      },
      movementVersion: 10,
    },
  ];

  const cashMovements = [
    { id: 101, cashRegisterId: 18, date: '2026-11-21T09:12:00-03:00', type: 'Sale', amount: 11600, responsible: 'Lucas Méndez', reason: 'Cobro en efectivo Venta #1041', saleId: 1041 },
    { id: 102, cashRegisterId: 18, date: '2026-11-21T10:05:00-03:00', type: 'Income', amount: 15000, responsible: 'Camila Ríos', reason: 'Refuerzo de cambio chico en billetes de $1.000', saleId: null },
    { id: 103, cashRegisterId: 18, date: '2026-11-21T11:25:00-03:00', type: 'Sale', amount: 10000, responsible: 'Lucas Méndez', reason: 'Pago mixto efectivo Venta #1042', saleId: 1042 },
    { id: 104, cashRegisterId: 18, date: '2026-11-21T12:18:00-03:00', type: 'Expense', amount: 8500, responsible: 'Camila Ríos', reason: 'Compra urgente de hielo y servilletas', saleId: null },
    { id: 105, cashRegisterId: 18, date: '2026-11-21T13:40:00-03:00', type: 'Sale', amount: 16500, responsible: 'Sofía Pereyra', reason: 'Cobro en efectivo Venta #1044', saleId: 1044 },
    { id: 106, cashRegisterId: 18, date: '2026-11-21T14:20:00-03:00', type: 'Withdrawal', amount: 20000, responsible: 'Camila Ríos', reason: 'Retiro parcial a caja fuerte por exceso de efectivo', saleId: null },
    { id: 107, cashRegisterId: 18, date: '2026-11-21T14:48:00-03:00', type: 'Refund', amount: 4200, responsible: 'Camila Ríos', reason: 'Devolución parcial Venta #1041 (Café con leche)', saleId: 1041 },
    // Historical register #17
    { id: 90, cashRegisterId: 17, date: '2026-11-20T12:30:00-03:00', type: 'Sale', amount: 86500, responsible: 'Lucas Méndez', reason: 'Cobros en efectivo turno mediodía', saleId: 1038 },
    { id: 91, cashRegisterId: 17, date: '2026-11-20T17:10:00-03:00', type: 'Expense', amount: 7500, responsible: 'Camila Ríos', reason: 'Reposición de gas para cocina', saleId: null },
  ];

  const sales = [
    {
      id: 1045,
      date: '2026-11-21T15:12:00-03:00',
      cashRegisterId: 18,
      operator: 'Lucas Méndez',
      status: 'Completed',
      items: [
        { lineId: 1, productId: 5, productName: 'Hamburguesa Clásica', quantity: 2, unitPrice: 13900, note: 'Una sin cebolla, punto jugoso', discountType: 'None', discountValue: 0, lineGross: 27800, lineDiscount: 0, lineSubtotal: 27800 },
        { lineId: 2, productId: 9, productName: 'Agua sin gas 500 ml', quantity: 2, unitPrice: 2600, note: '', discountType: 'None', discountValue: 0, lineGross: 5200, lineDiscount: 0, lineSubtotal: 5200 },
      ],
      subtotal: 33000,
      saleDiscountType: 'Percentage',
      saleDiscountValue: 10,
      saleDiscountAmount: 3300,
      total: 29700,
      payments: [
        { method: 'MercadoPago', amount: 29700, receivedAmount: null, changeAmount: 0 },
      ],
      stockConsumptions: [
        { ingredientId: 3, ingredientName: 'Pan brioche', quantity: 2, unit: 'unidad' },
        { ingredientId: 4, ingredientName: 'Carne picada especial', quantity: 0.36, unit: 'kg' },
        { ingredientId: 5, ingredientName: 'Queso cheddar', quantity: 0.12, unit: 'kg' },
        { ingredientId: 10, ingredientName: 'Papas bastón congeladas', quantity: 0.36, unit: 'kg' },
      ],
      refunds: [],
      cancellation: null,
    },
    {
      id: 1044,
      date: '2026-11-21T13:40:00-03:00',
      cashRegisterId: 18,
      operator: 'Sofía Pereyra',
      status: 'Completed',
      items: [
        { lineId: 1, productId: 6, productName: 'Milanesa Napolitana con fritas', quantity: 1, unitPrice: 16500, note: 'Bien cocida', discountType: 'None', discountValue: 0, lineGross: 16500, lineDiscount: 0, lineSubtotal: 16500 },
      ],
      subtotal: 16500,
      saleDiscountType: 'None',
      saleDiscountValue: 0,
      saleDiscountAmount: 0,
      total: 16500,
      payments: [
        { method: 'Cash', amount: 16500, receivedAmount: 20000, changeAmount: 3500 },
      ],
      stockConsumptions: [
        { ingredientId: 9, ingredientName: 'Nalga para milanesa', quantity: 0.26, unit: 'kg' },
        { ingredientId: 7, ingredientName: 'Jamón cocido natural', quantity: 0.06, unit: 'kg' },
        { ingredientId: 8, ingredientName: 'Queso tybo barra', quantity: 0.08, unit: 'kg' },
        { ingredientId: 10, ingredientName: 'Papas bastón congeladas', quantity: 0.24, unit: 'kg' },
      ],
      refunds: [],
      cancellation: null,
    },
    {
      id: 1043,
      date: '2026-11-21T12:45:00-03:00',
      cashRegisterId: 18,
      operator: 'Lucas Méndez',
      status: 'Cancelled',
      items: [
        { lineId: 1, productId: 4, productName: 'Tostado de jamón y queso', quantity: 2, unitPrice: 6800, note: '', discountType: 'None', discountValue: 0, lineGross: 13600, lineDiscount: 0, lineSubtotal: 13600 },
      ],
      subtotal: 13600,
      saleDiscountType: 'None',
      saleDiscountValue: 0,
      saleDiscountAmount: 0,
      total: 13600,
      payments: [
        { method: 'DebitCard', amount: 13600, receivedAmount: null, changeAmount: 0 },
      ],
      stockConsumptions: [
        { ingredientId: 7, ingredientName: 'Jamón cocido natural', quantity: 0.14, unit: 'kg' },
        { ingredientId: 8, ingredientName: 'Queso tybo barra', quantity: 0.16, unit: 'kg' },
      ],
      refunds: [],
      cancellation: {
        date: '2026-11-21T12:52:00-03:00',
        by: 'Camila Ríos',
        reason: 'Duplicado por error de terminal posnet.',
      },
    },
    {
      id: 1042,
      date: '2026-11-21T11:25:00-03:00',
      cashRegisterId: 18,
      operator: 'Lucas Méndez',
      status: 'Completed',
      items: [
        { lineId: 1, productId: 7, productName: 'Empanadas de carne (x3)', quantity: 2, unitPrice: 7500, note: 'Fritas', discountType: 'Fixed', discountValue: 1000, lineGross: 15000, lineDiscount: 1000, lineSubtotal: 14000 },
        { lineId: 2, productId: 10, productName: 'Brownie tibio con helado', quantity: 1, unitPrice: 6200, note: 'Helado aparte', discountType: 'None', discountValue: 0, lineGross: 6200, lineDiscount: 0, lineSubtotal: 6200 },
      ],
      subtotal: 20200,
      saleDiscountType: 'None',
      saleDiscountValue: 0,
      saleDiscountAmount: 0,
      total: 20200,
      payments: [
        { method: 'Cash', amount: 10000, receivedAmount: 10000, changeAmount: 0 },
        { method: 'DebitCard', amount: 10200, receivedAmount: null, changeAmount: 0 },
      ],
      stockConsumptions: [],
      refunds: [],
      cancellation: null,
    },
    {
      id: 1041,
      date: '2026-11-21T09:12:00-03:00',
      cashRegisterId: 18,
      operator: 'Lucas Méndez',
      status: 'Completed',
      items: [
        { lineId: 1, productId: 1, productName: 'Café con leche', quantity: 2, unitPrice: 4200, note: 'Uno tibio', discountType: 'None', discountValue: 0, lineGross: 8400, lineDiscount: 0, lineSubtotal: 8400 },
        { lineId: 2, productId: 3, productName: 'Medialunas de manteca (x2)', quantity: 1, unitPrice: 3200, note: '', discountType: 'None', discountValue: 0, lineGross: 3200, lineDiscount: 0, lineSubtotal: 3200 },
      ],
      subtotal: 11600,
      saleDiscountType: 'None',
      saleDiscountValue: 0,
      saleDiscountAmount: 0,
      total: 11600,
      payments: [
        { method: 'Cash', amount: 11600, receivedAmount: 12000, changeAmount: 400 },
      ],
      stockConsumptions: [
        { ingredientId: 1, ingredientName: 'Café en grano', quantity: 0.036, unit: 'kg' },
        { ingredientId: 2, ingredientName: 'Leche entera', quantity: 0.44, unit: 'lt' },
      ],
      refunds: [
        {
          id: 31,
          date: '2026-11-21T14:48:00-03:00',
          by: 'Camila Ríos',
          reason: 'Café salió frío y el cliente prefirió reintegro de una taza.',
          lines: [{ lineId: 1, productName: 'Café con leche', quantity: 1, disposition: 'Waste' }],
          payments: [{ method: 'Cash', amount: 4200 }],
          total: 4200,
        },
      ],
      cancellation: null,
    },
    {
      id: 1038,
      date: '2026-11-20T19:45:00-03:00',
      cashRegisterId: 17,
      operator: 'Sofía Pereyra',
      status: 'Completed',
      items: [
        { lineId: 1, productId: 2, productName: 'Flat White', quantity: 2, unitPrice: 4600, note: '', discountType: 'None', discountValue: 0, lineGross: 9200, lineDiscount: 0, lineSubtotal: 9200 },
      ],
      subtotal: 9200,
      saleDiscountType: 'None',
      saleDiscountValue: 0,
      saleDiscountAmount: 0,
      total: 9200,
      payments: [
        { method: 'Transfer', amount: 9200, receivedAmount: null, changeAmount: 0 },
      ],
      stockConsumptions: [],
      refunds: [],
      cancellation: null,
    },
  ];

  const stockMovements = [
    { id: 510, ingredientId: 3, date: '2026-11-21T15:12:00-03:00', type: 'SaleConsumption', delta: -2, before: 4, after: 2, reason: 'Venta #1045 (Hamburguesa Clásica x2)', wasteCategory: null, responsible: 'Lucas Méndez', sourceType: 'Sale', sourceId: 1045 },
    { id: 509, ingredientId: 4, date: '2026-11-21T15:12:00-03:00', type: 'SaleConsumption', delta: -0.36, before: 6.76, after: 6.4, reason: 'Venta #1045 (Hamburguesa Clásica x2)', wasteCategory: null, responsible: 'Lucas Méndez', sourceType: 'Sale', sourceId: 1045 },
    { id: 508, ingredientId: 5, date: '2026-11-21T15:12:00-03:00', type: 'SaleConsumption', delta: -0.12, before: 0.72, after: 0.6, reason: 'Venta #1045 (Hamburguesa Clásica x2)', wasteCategory: null, responsible: 'Lucas Méndez', sourceType: 'Sale', sourceId: 1045 },
    { id: 507, ingredientId: 6, date: '2026-11-21T11:40:00-03:00', type: 'Waste', delta: -1.2, before: 1.2, after: 0, reason: 'Cajón con limones en mal estado', wasteCategory: 'Vencimiento', responsible: 'Camila Ríos', sourceType: 'Manual', sourceId: null },
    { id: 506, ingredientId: 7, date: '2026-11-21T12:52:00-03:00', type: 'SaleCancellationReturn', delta: 0.14, before: 1.66, after: 1.8, reason: 'Anulación Venta #1043', wasteCategory: null, responsible: 'Camila Ríos', sourceType: 'Sale', sourceId: 1043 },
    { id: 505, ingredientId: 9, date: '2026-11-21T07:50:00-03:00', type: 'InvoiceReceipt', delta: 5.0, before: 0.5, after: 5.5, reason: 'Factura FC-A 0004-00018291', wasteCategory: null, responsible: 'Camila Ríos', sourceType: 'Invoice', sourceId: 204 },
    { id: 504, ingredientId: 2, date: '2026-11-20T18:10:00-03:00', type: 'CountAdjustment', delta: -0.5, before: 4.44, after: 3.94, reason: 'Diferencia hallada en conteo físico #12', wasteCategory: null, responsible: 'Camila Ríos', sourceType: 'StockCount', sourceId: 12 },
  ];

  const stockCounts = [
    {
      id: 12,
      date: '2026-11-20T18:10:00-03:00',
      responsible: 'Camila Ríos',
      notes: 'Control semanal de heladera y secos.',
      items: [
        { ingredientId: 2, ingredientName: 'Leche entera', unit: 'lt', expected: 4.44, counted: 3.94, diff: -0.5, reason: 'Sachet pinchado no registrado como merma' },
        { ingredientId: 1, ingredientName: 'Café en grano', unit: 'kg', expected: 4.5, counted: 4.5, diff: 0, reason: '' },
      ],
    },
  ];

  const businessSettings = {
    tradeName: 'Bistró Sur — Café & Cocina',
    legalName: 'Bistró Sur Gastronomía S.R.L.',
    cuit: '30-71684219-4',
    address: 'Thames 1642, Palermo, CABA',
    currency: 'ARS ($)',
    ivaCondition: 'Responsable Inscripto',
    maxEmployeeDiscountPct: 10,
    allowNegativeStock: false,
    enabledPayments: ['Cash', 'DebitCard', 'CreditCard', 'Transfer', 'MercadoPago', 'Other'],
    lowMarginThresholdPct: 30,
  };

  return {
    users,
    categories,
    products,
    ingredients,
    recipes,
    suppliers,
    invoices,
    cashRegisters,
    cashMovements,
    sales,
    stockMovements,
    stockCounts,
    businessSettings,
    nextIds: {
      category: 10,
      product: 20,
      ingredient: 20,
      recipe: 15,
      supplier: 10,
      invoice: 210,
      cashRegister: 19,
      cashMovement: 120,
      sale: 1046,
      refund: 35,
      stockMovement: 520,
      stockCount: 13,
    },
  };
}
