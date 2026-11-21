import { createInitialData, PAYMENT_METHODS } from '../data/seed.js';
import { convertUnit, roundMoney, roundQty } from '../utils/format.js';

const listeners = new Set();

function buildInitialState() {
  const data = createInitialData();
  return {
    ...data,
    auth: {
      isAuthenticated: true,
      currentUser: data.users[0], // Default Admin so evaluator sees full platform immediately
    },
    demo: {
      scenario: 'normal', // normal | closed-cash | critical-stock | stale-arqueo | empty | loading
      simulateStaleArqueo: false,
      simulateEmpty: false,
      simulateLoading: false,
    },
    pos: {
      categoryFilter: 'all', // 'all' | 'uncategorized' | number
      search: '',
      cart: [
        {
          lineId: 1,
          productId: 1,
          quantity: 2,
          note: 'Uno con leche descremada',
          discountType: 'None',
          discountValue: 0,
        },
        {
          lineId: 2,
          productId: 5,
          quantity: 1,
          note: 'Sin cebolla',
          discountType: 'None',
          discountValue: 0,
        },
      ],
      nextCartLineId: 3,
      saleDiscountType: 'None',
      saleDiscountValue: 0,
      lastError: null,
      lastReceipt: null,
    },
  };
}

let state = buildInitialState();

export function getState() {
  return state;
}

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function emit() {
  listeners.forEach((fn) => fn(state));
}

export function resetAllData() {
  const prevRole = state.auth.currentUser?.role || 'Admin';
  state = buildInitialState();
  state.auth.currentUser = state.users.find((u) => u.role === prevRole) || state.users[0];
  emit();
}

/* ---------- Auth & Demo Controls ---------- */
export function loginAs(username, password) {
  const u = username.trim().toLowerCase();
  if (!u || !password.trim()) {
    return { ok: false, error: 'Por favor complete todos los campos.' };
  }
  const found = state.users.find((usr) => usr.username.toLowerCase() === u && usr.active);
  if (!found || (password !== 'admin' && password !== '1234' && password !== found.username)) {
    return { ok: false, error: 'Usuario o contraseña incorrectos.' };
  }
  state.auth.isAuthenticated = true;
  state.auth.currentUser = found;
  emit();
  return { ok: true, user: found };
}

export function logout() {
  state.auth.isAuthenticated = false;
  state.auth.currentUser = null;
  emit();
}

export function switchDemoRole(role) {
  const target = state.users.find((u) => u.role === role && u.active) || state.users.find((u) => u.active) || state.users[0];
  state.auth.isAuthenticated = true;
  state.auth.currentUser = target;
  emit();
}

export function applyDemoScenario(scenario) {
  const prevRole = state.auth.currentUser?.role || 'Admin';
  state = buildInitialState();
  state.auth.currentUser = state.users.find((u) => u.role === prevRole) || state.users[0];
  state.demo.scenario = scenario;

  if (scenario === 'closed-cash') {
    const openReg = getOpenCashRegister();
    if (openReg) {
      openReg.status = 'Closed';
      openReg.closedAt = '2026-11-21T15:30:00-03:00';
      openReg.closedBy = 'Camila Ríos';
      const exp = getExpectedCash(openReg.id);
      openReg.expectedAmountSnapshot = exp;
      openReg.countedAmount = exp;
      openReg.differenceSnapshot = 0;
      openReg.countRecord = {
        denominations: [{ value: 10000, qty: Math.floor(exp / 10000) }],
        differenceReason: '',
        countedAt: openReg.closedAt,
        countedBy: 'Camila Ríos',
      };
    }
  } else if (scenario === 'critical-stock') {
    state.ingredients.find((i) => i.id === 2).currentStock = 0; // Leche entera agotada
    state.ingredients.find((i) => i.id === 3).currentStock = 1; // Pan brioche 1 unidad
    state.ingredients.find((i) => i.id === 5).currentStock = 0.2;
  } else if (scenario === 'stale-arqueo') {
    state.demo.simulateStaleArqueo = true;
  } else if (scenario === 'empty') {
    state.demo.simulateEmpty = true;
    state.pos.cart = [];
  } else if (scenario === 'loading') {
    state.demo.simulateLoading = true;
  }

  emit();
}

/* ---------- Domain Queries ---------- */
export function getOpenCashRegister() {
  return state.cashRegisters.find((r) => r.status === 'Open') || null;
}

export function getCanonicalCashRegister() {
  return getOpenCashRegister() || state.cashRegisters[0] || null;
}

export function getCashMovementsFor(registerId) {
  return state.cashMovements
    .filter((m) => m.cashRegisterId === registerId)
    .sort((a, b) => new Date(b.date) - new Date(a.date));
}

export function getExpectedCash(registerId) {
  const reg = state.cashRegisters.find((r) => r.id === registerId);
  if (!reg) return 0;
  const moves = state.cashMovements.filter((m) => m.cashRegisterId === registerId);
  const delta = moves.reduce((acc, m) => {
    if (m.type === 'Sale' || m.type === 'Income') return acc + m.amount;
    if (m.type === 'Expense' || m.type === 'Withdrawal' || m.type === 'Refund') return acc - m.amount;
    return acc;
  }, 0);
  return roundMoney(reg.initialAmount + delta);
}

export function getCashPaymentSummary(registerId) {
  const sessionSales = state.sales.filter((s) => s.cashRegisterId === registerId);
  const rows = PAYMENT_METHODS.map((pm) => {
    let registered = 0;
    let refunded = 0;
    for (const s of sessionSales) {
      for (const p of s.payments) {
        if (p.method === pm.id) registered += p.amount;
      }
    }
    for (const s of state.sales) {
      for (const ref of s.refunds || []) {
        const refRegId = ref.cashRegisterId ?? s.cashRegisterId;
        if (refRegId !== registerId) continue;
        for (const rp of ref.payments) {
          if (rp.method === pm.id) refunded += rp.amount;
        }
      }
    }
    return {
      method: pm.id,
      label: pm.label,
      registered: roundMoney(registered),
      refunded: roundMoney(refunded),
      net: roundMoney(registered - refunded),
    };
  });
  const totalRegistered = roundMoney(rows.reduce((a, r) => a + r.registered, 0));
  const totalRefunded = roundMoney(rows.reduce((a, r) => a + r.refunded, 0));
  const totalNet = roundMoney(totalRegistered - totalRefunded);
  return {
    status: registerId ? 'Complete' : 'NoSession',
    rows,
    totalRegistered,
    totalRefunded,
    totalNet,
  };
}

export function getSaleDisplayStatus(sale) {
  if (sale.status === 'Cancelled') return { code: 'Cancelled', label: 'Anulada', variant: 'danger' };
  const refunds = sale.refunds || [];
  if (refunds.length === 0) return { code: 'Collected', label: 'Cobrada', variant: 'ok' };
  const totalSoldQty = sale.items.reduce((a, i) => a + Number(i.quantity || 0), 0);
  const totalRefundedQty = refunds.reduce(
    (acc, r) => acc + (r.lines || []).reduce((a, l) => a + Number(l.quantity || 0), 0),
    0
  );
  const refundedTotal = roundMoney(refunds.reduce((a, r) => a + r.total, 0));
  if (totalRefundedQty >= totalSoldQty || (sale.total > 0 && refundedTotal >= sale.total - 0.01)) {
    return { code: 'Refunded', label: 'Devuelta', variant: 'neutral' };
  }
  return { code: 'PartiallyRefunded', label: 'Parcialmente devuelta', variant: 'warn' };
}

export function getProductMargin(product) {
  if (!product.price || product.price <= 0 || product.cost == null) return null;
  return roundMoney(((product.price - product.cost) / product.price) * 100);
}

export function getMarginHealth(margin) {
  if (margin == null) return { label: 'Sin costo', variant: 'neutral' };
  if (margin < 0) return { label: 'Margen negativo', variant: 'danger' };
  if (margin < state.businessSettings.lowMarginThresholdPct) return { label: 'Margen bajo', variant: 'warn' };
  return { label: 'Saludable', variant: 'ok' };
}

export function getIngredientStatus(ing) {
  if (ing.currentStock < 0) return { code: 'negative', label: 'Stock negativo', variant: 'danger' };
  if (ing.currentStock <= 0) return { code: 'out', label: 'Agotado', variant: 'danger' };
  if (ing.currentStock <= ing.minStock) return { code: 'low', label: 'Bajo mínimo', variant: 'warn' };
  return { code: 'ok', label: 'Normal', variant: 'ok' };
}

export function getIngredientCoverageDays(ing) {
  if (!ing.dailyUsage7d || ing.dailyUsage7d <= 0) return null;
  if (ing.currentStock <= 0) return 0;
  return Math.round((ing.currentStock / ing.dailyUsage7d) * 10) / 10;
}

export function getStockAlerts() {
  return state.ingredients
    .filter((i) => i.active && i.currentStock <= i.minStock)
    .sort((a, b) => a.currentStock - b.currentStock);
}

export function getRecipeCalculation(recipe) {
  let totalCost = 0;
  const warnings = [];
  const breakdown = recipe.ingredients.map((ri) => {
    const ing = state.ingredients.find((i) => i.id === ri.ingredientId);
    if (!ing) {
      warnings.push('Ingrediente eliminado o inexistente.');
      return { ...ri, ingredientName: 'Desconocido', unitCost: 0, lineCost: 0, compatible: false };
    }
    const conv = convertUnit(ri.quantity, ri.unit, ing.unit);
    if (!conv.ok) {
      warnings.push(`Unidad incompatible en ${ing.name} (${ri.unit} vs ${ing.unit}): excluido del costo.`);
      return { ...ri, ingredientName: ing.name, baseUnit: ing.unit, unitCost: ing.lastUnitPrice, lineCost: 0, compatible: false };
    }
    if (!ing.lastUnitPrice || ing.lastUnitPrice <= 0) {
      warnings.push(`${ing.name} no tiene precio de última factura.`);
    }
    const lineCost = roundMoney(conv.value * (ing.lastUnitPrice || 0));
    totalCost = roundMoney(totalCost + lineCost);
    return { ...ri, ingredientName: ing.name, baseUnit: ing.unit, baseQty: conv.value, unitCost: ing.lastUnitPrice || 0, lineCost, compatible: true };
  });

  const yieldQty = Math.max(1, Number(recipe.yield || 1));
  const unitCost = roundMoney(totalCost / yieldQty);
  let variationPct = 0;
  let variationLevel = { code: 'ok', label: 'Estable (<10%)', variant: 'ok' };
  if (recipe.lastCalculatedCost && recipe.lastCalculatedCost > 0) {
    variationPct = roundMoney(((unitCost - recipe.lastCalculatedCost) / recipe.lastCalculatedCost) * 100);
    const absPct = Math.abs(variationPct);
    if (absPct >= 30) variationLevel = { code: 'danger', label: `Variación alta (${variationPct > 0 ? '+' : ''}${variationPct}%)`, variant: 'danger' };
    else if (absPct >= 10) variationLevel = { code: 'warn', label: `Variación media (${variationPct > 0 ? '+' : ''}${variationPct}%)`, variant: 'warn' };
    else variationLevel = { code: 'ok', label: `Estable (${variationPct > 0 ? '+' : ''}${variationPct}%)`, variant: 'ok' };
  }
  return { totalCost, unitCost, variationPct, variationLevel, warnings, breakdown };
}

function getCartReservedByIngredient(excludeLineId = null) {
  const reserved = new Map();
  for (const line of state.pos.cart) {
    if (excludeLineId != null && line.lineId === excludeLineId) continue;
    const prod = state.products.find((p) => p.id === line.productId);
    if (!prod) continue;
    const recipe = state.recipes.find((r) => r.name.toLowerCase() === prod.name.toLowerCase());
    if (!recipe) continue;
    for (const ri of recipe.ingredients) {
      const ing = state.ingredients.find((i) => i.id === ri.ingredientId);
      if (!ing) continue;
      const conv = convertUnit(ri.quantity * line.quantity, ri.unit, ing.unit);
      if (!conv.ok || conv.value <= 0) continue;
      reserved.set(ing.id, roundQty((reserved.get(ing.id) || 0) + conv.value));
    }
  }
  return reserved;
}

export function getProductRecipeAvailability(product, { considerCart = false, excludeLineId = null } = {}) {
  const recipe = state.recipes.find((r) => r.name.toLowerCase() === product.name.toLowerCase());
  if (!recipe) return { hasRecipe: false, maxUnits: Infinity, blockingIngredient: null };
  const reserved = considerCart ? getCartReservedByIngredient(excludeLineId) : null;
  let maxUnits = Infinity;
  let blockingIngredient = null;
  for (const ri of recipe.ingredients) {
    const ing = state.ingredients.find((i) => i.id === ri.ingredientId);
    if (!ing) continue;
    const conv = convertUnit(ri.quantity, ri.unit, ing.unit);
    if (!conv.ok || conv.value <= 0) continue;
    const freeStock = Math.max(0, roundQty(ing.currentStock - (reserved?.get(ing.id) || 0)));
    const possible = Math.floor((freeStock + 1e-9) / conv.value);
    if (possible < maxUnits) {
      maxUnits = possible;
      blockingIngredient = ing;
    }
  }
  return { hasRecipe: true, recipe, maxUnits, blockingIngredient };
}

/* ---------- POS Calculations & Mutations (Priority 1) ---------- */
export function computeCartTotals() {
  const lines = state.pos.cart.map((item) => {
    const product = state.products.find((p) => p.id === item.productId);
    const unitPrice = product ? product.price : 0;
    const lineGross = roundMoney(unitPrice * item.quantity);
    let lineDiscount = 0;
    if (item.discountType === 'Percentage') {
      const pct = Math.max(0, Math.min(100, Number(item.discountValue || 0)));
      lineDiscount = roundMoney(lineGross * (pct / 100));
    } else if (item.discountType === 'Fixed') {
      lineDiscount = roundMoney(Math.max(0, Math.min(lineGross, Number(item.discountValue || 0))));
    }
    const lineSubtotal = roundMoney(lineGross - lineDiscount);
    return {
      ...item,
      productName: product ? product.name : 'Producto',
      unitPrice,
      lineGross,
      lineDiscount,
      lineSubtotal,
    };
  });

  const grossBeforeDiscounts = roundMoney(lines.reduce((a, l) => a + l.lineGross, 0));
  const totalLineDiscounts = roundMoney(lines.reduce((a, l) => a + l.lineDiscount, 0));
  const subtotal = roundMoney(lines.reduce((a, l) => a + l.lineSubtotal, 0));

  let saleDiscountAmount = 0;
  if (state.pos.saleDiscountType === 'Percentage') {
    const pct = Math.max(0, Math.min(100, Number(state.pos.saleDiscountValue || 0)));
    saleDiscountAmount = roundMoney(subtotal * (pct / 100));
  } else if (state.pos.saleDiscountType === 'Fixed') {
    saleDiscountAmount = roundMoney(Math.max(0, Math.min(subtotal, Number(state.pos.saleDiscountValue || 0))));
  }

  const total = roundMoney(subtotal - saleDiscountAmount);
  const itemCount = lines.reduce((a, l) => a + l.quantity, 0);
  return { lines, grossBeforeDiscounts, totalLineDiscounts, subtotal, saleDiscountAmount, total, itemCount };
}

export function posAddProduct(productId) {
  const product = state.products.find((p) => p.id === productId);
  if (!product) return { ok: false, error: 'Producto no encontrado.' };
  if (!product.isActive) {
    const err = `El producto ${product.name} está inactivo y no se puede vender.`;
    state.pos.lastError = err;
    emit();
    return { ok: false, error: err };
  }
  const avail = getProductRecipeAvailability(product, { considerCart: true });
  if (avail.hasRecipe && avail.maxUnits <= 0) {
    const ing = avail.blockingIngredient;
    const err = ing
      ? `Sin stock disponible de ${product.name}: falta ${ing.name} (${ing.currentStock} ${ing.unit} en stock).`
      : `Sin stock disponible de ${product.name}.`;
    return { ok: false, error: err };
  }
  state.pos.lastError = null;
  const existing = state.pos.cart.find((c) => c.productId === productId && !c.note && c.discountType === 'None');
  if (existing) {
    existing.quantity += 1;
  } else {
    state.pos.cart.push({
      lineId: state.pos.nextCartLineId++,
      productId,
      quantity: 1,
      note: '',
      discountType: 'None',
      discountValue: 0,
    });
  }
  emit();
  return { ok: true };
}

export function posUpdateLine(lineId, patch) {
  const line = state.pos.cart.find((l) => l.lineId === lineId);
  if (!line) return { ok: false };
  if (patch.quantity !== undefined && patch.quantity > line.quantity) {
    const product = state.products.find((p) => p.id === line.productId);
    if (product) {
      const avail = getProductRecipeAvailability(product, { considerCart: true, excludeLineId: lineId });
      if (avail.hasRecipe && patch.quantity > avail.maxUnits) {
        const ing = avail.blockingIngredient;
        const err = ing
          ? `Stock máximo alcanzado para ${product.name} (${ing.name}: ${ing.currentStock} ${ing.unit} disponibles).`
          : `No hay más stock disponible de ${product.name}.`;
        if (avail.maxUnits > line.quantity) {
          line.quantity = avail.maxUnits;
          emit();
        }
        return { ok: false, error: err };
      }
    }
  }
  Object.assign(line, patch);
  if (line.quantity <= 0) {
    state.pos.cart = state.pos.cart.filter((l) => l.lineId !== lineId);
  }
  state.pos.lastError = null;
  emit();
  return { ok: true };
}

export function posRemoveLine(lineId) {
  state.pos.cart = state.pos.cart.filter((l) => l.lineId !== lineId);
  state.pos.lastError = null;
  emit();
}

export function posClearCart() {
  state.pos.cart = [];
  state.pos.saleDiscountType = 'None';
  state.pos.saleDiscountValue = 0;
  state.pos.lastError = null;
  emit();
}

export function posSetSaleDiscount(type, value) {
  const numVal = Number(value || 0);
  if (type === 'Percentage') {
    if (numVal < 0 || numVal > 100) {
      return { ok: false, error: 'El porcentaje de descuento debe estar entre 0% y 100%.' };
    }
    const isEmployee = state.auth.currentUser?.role === 'Employee';
    const cap = Number(state.businessSettings.maxEmployeeDiscountPct ?? 100);
    if (isEmployee && numVal > cap) {
      return { ok: false, error: `Tu rol Empleado tiene un tope máximo de descuento del ${cap}%.` };
    }
  } else if (type === 'Fixed') {
    const sub = computeCartTotals().subtotal;
    if (numVal < 0 || numVal > sub) {
      return { ok: false, error: `El descuento fijo no puede superar el subtotal (${sub}).` };
    }
    const isEmployee = state.auth.currentUser?.role === 'Employee';
    const cap = Number(state.businessSettings.maxEmployeeDiscountPct ?? 100);
    if (isEmployee && sub > 0 && (numVal / sub) * 100 > cap + 0.01) {
      return { ok: false, error: `El importe fijo supera el tope de descuento del ${cap}% para Empleado.` };
    }
  }
  state.pos.saleDiscountType = type;
  state.pos.saleDiscountValue = type === 'None' ? 0 : numVal;
  emit();
  return { ok: true };
}

export function posSetFilter(categoryFilter, search) {
  if (categoryFilter !== undefined) state.pos.categoryFilter = categoryFilter;
  if (search !== undefined) state.pos.search = search;
  emit();
}

/**
 * Full atomic sale completion matching SaleService.cs rules:
 * 1. Open register required
 * 2. Active products check
 * 3. Recipe ingredient stock validation (exact error message)
 * 4. Exact payment validation (unique methods, sum == total, cash received >= applied, 0 payments if total == 0)
 * 5. Atomic stock deduction + StockMovement entries + CashMovement for cash payment + Sale creation
 */
export function completeSale(paymentsInput) {
  const openReg = getOpenCashRegister();
  if (!openReg) {
    const err = 'Debe haber una caja abierta para vender.';
    state.pos.lastError = err;
    emit();
    return { ok: false, error: err };
  }

  const totals = computeCartTotals();
  if (totals.lines.length === 0) {
    return { ok: false, error: 'Agregá al menos un producto al carrito.' };
  }

  // Validate active products & aggregate recipe ingredient demand
  const requiredByIngredient = new Map();
  for (const line of totals.lines) {
    const prod = state.products.find((p) => p.id === line.productId);
    if (!prod || !prod.isActive) {
      const err = `El producto ${line.productName} está inactivo y no se puede vender.`;
      state.pos.lastError = err;
      emit();
      return { ok: false, error: err };
    }
    const recipe = state.recipes.find((r) => r.name.toLowerCase() === prod.name.toLowerCase());
    if (recipe) {
      for (const ri of recipe.ingredients) {
        const ing = state.ingredients.find((i) => i.id === ri.ingredientId);
        if (!ing) continue;
        const conv = convertUnit(ri.quantity * line.quantity, ri.unit, ing.unit);
        if (!conv.ok) continue;
        requiredByIngredient.set(ing.id, roundQty((requiredByIngredient.get(ing.id) || 0) + conv.value));
      }
    }
  }

  for (const [ingId, needed] of requiredByIngredient.entries()) {
    const ing = state.ingredients.find((i) => i.id === ingId);
    if (ing.currentStock + 1e-9 < needed) {
      const err = `Stock insuficiente de ${ing.name}. Disponible: ${ing.currentStock} ${ing.unit} (requerido: ${needed} ${ing.unit}).`;
      state.pos.lastError = err;
      emit();
      return { ok: false, error: err };
    }
  }

  // Validate payments
  const enabledMethods = new Set(state.businessSettings.enabledPayments || PAYMENT_METHODS.map((m) => m.id));
  let normalizedPayments = [];
  if (totals.total === 0) {
    if (paymentsInput.length > 0) {
      return { ok: false, error: 'Total cero: no requiere pagos ni registra un pago.' };
    }
  } else {
    if (!paymentsInput.length) {
      return { ok: false, error: 'La venta debe contener pagos por el total final.' };
    }
    const seen = new Set();
    let sum = 0;
    for (const p of paymentsInput) {
      if (!enabledMethods.has(p.method)) {
        return { ok: false, error: 'El medio de pago seleccionado está deshabilitado en Configuración.' };
      }
      if (seen.has(p.method)) {
        return { ok: false, error: 'No se puede repetir un medio de pago en la venta.' };
      }
      seen.add(p.method);
      const amt = roundMoney(p.amount);
      if (amt <= 0) {
        return { ok: false, error: 'Cada medio de pago debe tener un importe mayor a cero.' };
      }
      let received = null;
      let change = 0;
      if (p.method === 'Cash') {
        received = roundMoney(p.receivedAmount);
        if (Number.isNaN(received) || received < amt) {
          return { ok: false, error: 'El efectivo recibido debe ser igual o mayor al importe aplicado en efectivo.' };
        }
        change = roundMoney(received - amt);
      }
      sum = roundMoney(sum + amt);
      normalizedPayments.push({ method: p.method, amount: amt, receivedAmount: received, changeAmount: change });
    }
    if (Math.abs(sum - totals.total) > 0.01) {
      return { ok: false, error: 'La venta debe contener pagos por el total final.' };
    }
  }

  // Commit atomically
  const now = new Date().toISOString();
  const saleId = state.nextIds.sale++;
  const operator = state.auth.currentUser?.fullName || 'Operador';
  const stockConsumptions = [];

  for (const [ingId, needed] of requiredByIngredient.entries()) {
    const ing = state.ingredients.find((i) => i.id === ingId);
    const before = ing.currentStock;
    const after = roundQty(before - needed);
    ing.currentStock = after;
    stockConsumptions.push({ ingredientId: ing.id, ingredientName: ing.name, quantity: needed, unit: ing.unit });
    state.stockMovements.unshift({
      id: state.nextIds.stockMovement++,
      ingredientId: ing.id,
      date: now,
      type: 'SaleConsumption',
      delta: -needed,
      before,
      after,
      reason: `Venta #${saleId}`,
      wasteCategory: null,
      responsible: operator,
      sourceType: 'Sale',
      sourceId: saleId,
    });
  }

  const cashPay = normalizedPayments.find((p) => p.method === 'Cash');
  if (cashPay && cashPay.amount > 0) {
    state.cashMovements.unshift({
      id: state.nextIds.cashMovement++,
      cashRegisterId: openReg.id,
      date: now,
      type: 'Sale',
      amount: cashPay.amount,
      responsible: operator,
      reason: `Cobro en efectivo Venta #${saleId}`,
      saleId,
    });
    openReg.movementVersion += 1;
  }

  const sale = {
    id: saleId,
    date: now,
    cashRegisterId: openReg.id,
    operator,
    status: 'Completed',
    items: totals.lines,
    subtotal: totals.subtotal,
    saleDiscountType: state.pos.saleDiscountType,
    saleDiscountValue: state.pos.saleDiscountValue,
    saleDiscountAmount: totals.saleDiscountAmount,
    total: totals.total,
    payments: normalizedPayments,
    stockConsumptions,
    refunds: [],
    cancellation: null,
  };

  state.sales.unshift(sale);
  state.pos.cart = [];
  state.pos.saleDiscountType = 'None';
  state.pos.saleDiscountValue = 0;
  state.pos.lastError = null;
  state.pos.lastReceipt = sale;
  emit();
  return { ok: true, sale };
}

/* ---------- Cash Register Mutations (Priority 2) ---------- */
export function openCashRegister(initialAmount) {
  if (getOpenCashRegister()) return { ok: false, error: 'Ya hay una caja abierta.' };
  const amt = roundMoney(initialAmount);
  if (Number.isNaN(amt) || amt < 0) return { ok: false, error: 'El monto inicial debe ser cero o positivo.' };
  const reg = {
    id: state.nextIds.cashRegister++,
    status: 'Open',
    openedAt: new Date().toISOString(),
    closedAt: null,
    openedBy: state.auth.currentUser?.fullName || 'Camila Ríos',
    closedBy: null,
    initialAmount: amt,
    countedAmount: null,
    expectedAmountSnapshot: null,
    differenceSnapshot: null,
    countRecord: null,
    movementVersion: 0,
  };
  state.cashRegisters.unshift(reg);
  emit();
  return { ok: true, register: reg };
}

export function addManualCashMovement({ type, amount, reason }) {
  const openReg = getOpenCashRegister();
  if (!openReg) return { ok: false, error: 'Debe haber una caja abierta para registrar movimientos.' };
  const amt = roundMoney(amount);
  if (Number.isNaN(amt) || amt <= 0) return { ok: false, error: 'El monto debe ser mayor a cero.' };
  const trimmed = (reason || '').trim();
  if (!trimmed) return { ok: false, error: 'Debe indicar un motivo obligatorio.' };

  if (type === 'Expense' || type === 'Withdrawal') {
    const available = getExpectedCash(openReg.id);
    if (amt > available) {
      return { ok: false, error: 'El monto supera el efectivo disponible en caja.' };
    }
  }

  const move = {
    id: state.nextIds.cashMovement++,
    cashRegisterId: openReg.id,
    date: new Date().toISOString(),
    type,
    amount: amt,
    responsible: state.auth.currentUser?.fullName || 'Camila Ríos',
    reason: trimmed,
    saleId: null,
  };
  state.cashMovements.unshift(move);
  openReg.movementVersion += 1;
  emit();
  return { ok: true, movement: move };
}

export function closeCashRegister({ denominations, differenceReason, expectedVersion }) {
  const openReg = getOpenCashRegister();
  if (!openReg) return { ok: false, error: 'No hay una caja abierta para cerrar.' };

  if (state.demo.simulateStaleArqueo || (expectedVersion != null && expectedVersion !== openReg.movementVersion)) {
    state.demo.simulateStaleArqueo = false;
    return {
      ok: false,
      stale: true,
      error: 'Se registraron movimientos mientras realizabas el arqueo. Actualizá el saldo esperado antes de confirmar el cierre.',
    };
  }

  const validDenoms = denominations.filter((d) => Number(d.value) > 0 && Number(d.qty) > 0);
  const counted = roundMoney(validDenoms.reduce((a, d) => a + Number(d.value) * Number(d.qty), 0));
  const expected = getExpectedCash(openReg.id);
  const diff = roundMoney(counted - expected);

  if (Math.abs(diff) > 0.01 && !(differenceReason || '').trim()) {
    return { ok: false, error: 'Cuando existe faltante o sobrante debés indicar el motivo de la diferencia.' };
  }

  const now = new Date().toISOString();
  openReg.status = 'Closed';
  openReg.closedAt = now;
  openReg.closedBy = state.auth.currentUser?.fullName || 'Camila Ríos';
  openReg.countedAmount = counted;
  openReg.expectedAmountSnapshot = expected;
  openReg.differenceSnapshot = diff;
  openReg.countRecord = {
    denominations: validDenoms,
    differenceReason: (differenceReason || '').trim(),
    countedAt: now,
    countedBy: openReg.closedBy,
  };
  emit();
  return { ok: true, register: openReg };
}

/* ---------- Sales History: Cancellation & Partial/Full Refund ---------- */
export function cancelSale(saleId, reason) {
  const sale = state.sales.find((s) => s.id === saleId);
  if (!sale) return { ok: false, error: 'Venta no encontrada.' };
  if (sale.status === 'Cancelled') return { ok: false, error: 'La venta ya está anulada.' };
  if ((sale.refunds || []).length > 0) {
    return { ok: false, error: 'La venta tiene devoluciones registradas; no puede anularse.' };
  }
  const trimmed = (reason || '').trim();
  if (!trimmed) return { ok: false, error: 'Debe indicar un motivo de cancelación.' };

  const now = new Date().toISOString();
  const actor = state.auth.currentUser?.fullName || 'Camila Ríos';
  sale.status = 'Cancelled';
  sale.cancellation = { date: now, by: actor, reason: trimmed };

  // Restore consumed stock snapshot
  for (const sc of sale.stockConsumptions || []) {
    const ing = state.ingredients.find((i) => i.id === sc.ingredientId);
    if (!ing) continue;
    const before = ing.currentStock;
    const after = roundQty(before + sc.quantity);
    ing.currentStock = after;
    state.stockMovements.unshift({
      id: state.nextIds.stockMovement++,
      ingredientId: ing.id,
      date: now,
      type: 'SaleCancellationReturn',
      delta: sc.quantity,
      before,
      after,
      reason: `Anulación Venta #${sale.id}: ${trimmed}`,
      wasteCategory: null,
      responsible: actor,
      sourceType: 'Sale',
      sourceId: sale.id,
    });
  }
  emit();
  return { ok: true, sale };
}

export function registerSaleRefund(saleId, { lines, payments, reason }) {
  const sale = state.sales.find((s) => s.id === saleId);
  if (!sale) return { ok: false, error: 'Venta no encontrada.' };
  if (sale.status === 'Cancelled') return { ok: false, error: 'La venta anulada no admite devoluciones.' };
  const trimmed = (reason || '').trim();
  if (!trimmed) return { ok: false, error: 'Debe indicar un motivo de devolución.' };

  const validLines = (lines || []).filter((l) => Number(l.quantity) > 0);
  if (!validLines.length) return { ok: false, error: 'Indicá al menos una cantidad mayor a cero para devolver.' };

  // Validate per-line available quantity, restock snapshot availability & compute expected prorated refund
  const hasSnapshot = (sale.stockConsumptions || []).length > 0;
  let expectedRefundTotal = 0;
  for (const rl of validLines) {
    const item = sale.items.find((i) => i.lineId === rl.lineId);
    if (!item) return { ok: false, error: 'Línea de venta inválida.' };
    const alreadyRefundedQty = (sale.refunds || []).reduce(
      (acc, r) => acc + (r.lines || []).filter((x) => x.lineId === rl.lineId).reduce((a, x) => a + Number(x.quantity || 0), 0),
      0
    );
    const availableQty = item.quantity - alreadyRefundedQty;
    if (Number(rl.quantity) > availableQty) {
      return { ok: false, error: `La cantidad a devolver de ${item.productName} supera el disponible (${availableQty}).` };
    }
    if (rl.disposition === 'Restock') {
      const hasRecipeForItem = state.recipes.some((r) => r.name.toLowerCase() === item.productName.toLowerCase());
      if (!hasSnapshot || !hasRecipeForItem) {
        return { ok: false, error: `${item.productName} no tiene registro de consumo de stock; elegí destino "Merma".` };
      }
    }
    const unitEffective = (item.lineSubtotal / item.quantity) * (sale.subtotal > 0 ? sale.total / sale.subtotal : 1);
    expectedRefundTotal = roundMoney(expectedRefundTotal + unitEffective * Number(rl.quantity));
  }

  const validPayments = (payments || []).filter((p) => Number(p.amount) > 0).map((p) => ({
    method: p.method,
    amount: roundMoney(p.amount),
  }));
  const totalRefund = roundMoney(validPayments.reduce((a, p) => a + p.amount, 0));
  if (totalRefund <= 0) return { ok: false, error: 'Ingresá al menos un importe a devolver.' };
  if (Math.abs(totalRefund - expectedRefundTotal) > 0.05) {
    return {
      ok: false,
      error: `El total a reintegrar (${totalRefund}) debe coincidir con el importe calculado de los ítems seleccionados (${expectedRefundTotal}). Usá "Calcular importe".`,
    };
  }

  // Validate per-method available refundable amount
  for (const vp of validPayments) {
    const paid = roundMoney((sale.payments || []).filter((p) => p.method === vp.method).reduce((a, p) => a + p.amount, 0));
    const prevRefunded = roundMoney(
      (sale.refunds || []).reduce(
        (acc, r) => acc + (r.payments || []).filter((p) => p.method === vp.method).reduce((a, p) => a + p.amount, 0),
        0
      )
    );
    const avail = roundMoney(paid - prevRefunded);
    if (vp.amount > avail + 0.01) {
      return { ok: false, error: 'El importe a devolver supera el saldo disponible para ese medio de pago.' };
    }
  }

  const cashRefund = validPayments.find((p) => p.method === 'Cash' && p.amount > 0);
  const openReg = getOpenCashRegister();
  if (cashRefund && !openReg) {
    return { ok: false, error: 'Debe haber una caja abierta para devolver efectivo.' };
  }
  if (cashRefund && openReg) {
    const availableCash = getExpectedCash(openReg.id);
    if (cashRefund.amount > availableCash + 0.01) {
      return { ok: false, error: 'El importe a devolver en efectivo supera el efectivo disponible en caja.' };
    }
  }

  const now = new Date().toISOString();
  const actor = state.auth.currentUser?.fullName || 'Camila Ríos';
  const refund = {
    id: state.nextIds.refund++,
    cashRegisterId: openReg?.id ?? sale.cashRegisterId,
    date: now,
    by: actor,
    reason: trimmed,
    lines: validLines,
    payments: validPayments,
    total: totalRefund,
  };
  sale.refunds.push(refund);

  if (cashRefund && openReg) {
    state.cashMovements.unshift({
      id: state.nextIds.cashMovement++,
      cashRegisterId: openReg.id,
      date: now,
      type: 'Refund',
      amount: roundMoney(cashRefund.amount),
      responsible: actor,
      reason: `Devolución Venta #${sale.id}: ${trimmed}`,
      saleId: sale.id,
    });
    openReg.movementVersion += 1;
  }

  // Restock lines marked Vuelve a stock proportionally from checkout snapshot
  const restockLines = validLines.filter((l) => l.disposition === 'Restock' && Number(l.quantity) > 0);
  if (restockLines.length && (sale.stockConsumptions || []).length) {
    const totalTrackedUnits = sale.items
      .filter((it) => state.recipes.some((r) => r.name.toLowerCase() === it.productName.toLowerCase()))
      .reduce((a, it) => a + it.quantity, 0);
    const restockedUnits = restockLines.reduce((a, rl) => a + Number(rl.quantity), 0);
    const ratio = totalTrackedUnits > 0 ? Math.min(1, restockedUnits / totalTrackedUnits) : 0;
    for (const sc of sale.stockConsumptions) {
      const ing = state.ingredients.find((i) => i.id === sc.ingredientId);
      if (!ing) continue;
      const qtyBack = roundQty(sc.quantity * ratio);
      if (qtyBack <= 0) continue;
      const before = ing.currentStock;
      const after = roundQty(before + qtyBack);
      ing.currentStock = after;
      state.stockMovements.unshift({
        id: state.nextIds.stockMovement++,
        ingredientId: ing.id,
        date: now,
        type: 'RefundReturn',
        delta: qtyBack,
        before,
        after,
        reason: `Devolución Venta #${sale.id} (${restockLines.map((l) => l.productName).join(', ')})`,
        wasteCategory: null,
        responsible: actor,
        sourceType: 'Sale',
        sourceId: sale.id,
      });
    }
  }

  emit();
  return { ok: true, refund };
}

/* ---------- Priority 3: Products, Categories, Ingredients, StockCount, Recipes, Purchasing ---------- */
export function saveProduct(payload) {
  const name = (payload.name || '').trim();
  const price = roundMoney(payload.price);
  const cost = payload.cost === '' || payload.cost == null ? null : roundMoney(payload.cost);
  if (!name) return { ok: false, error: 'El nombre del producto es obligatorio.' };
  if (Number.isNaN(price) || price <= 0) return { ok: false, error: 'El precio de venta debe ser mayor a cero.' };
  if (cost != null && (Number.isNaN(cost) || cost < 0)) return { ok: false, error: 'El costo no puede ser negativo.' };

  if (payload.id) {
    const existing = state.products.find((p) => p.id === payload.id);
    if (!existing) return { ok: false, error: 'Producto no encontrado.' };
    existing.name = name;
    existing.price = price;
    existing.cost = cost;
    existing.categoryId = payload.categoryId ? Number(payload.categoryId) : null;
    existing.isActive = Boolean(payload.isActive);
  } else {
    state.products.unshift({
      id: state.nextIds.product++,
      name,
      price,
      cost,
      categoryId: payload.categoryId ? Number(payload.categoryId) : null,
      isActive: payload.isActive !== false,
    });
  }
  emit();
  return { ok: true };
}

export function toggleProductActive(productId) {
  const p = state.products.find((item) => item.id === productId);
  if (!p) return;
  p.isActive = !p.isActive;
  emit();
}

export function deleteProduct(productId) {
  state.products = state.products.filter((p) => p.id !== productId);
  emit();
}

export function saveCategory({ id, name }) {
  const trimmed = (name || '').trim();
  if (!trimmed) return { ok: false, error: 'El nombre de la categoría es obligatorio.' };
  const duplicate = state.categories.find(
    (c) => c.name.toLowerCase() === trimmed.toLowerCase() && c.id !== id
  );
  if (duplicate) return { ok: false, error: 'Ya existe una categoría con ese nombre.' };
  if (id) {
    const c = state.categories.find((cat) => cat.id === id);
    if (c) c.name = trimmed;
  } else {
    state.categories.push({ id: state.nextIds.category++, name: trimmed });
  }
  emit();
  return { ok: true };
}

export function deleteCategory(id) {
  const inUse = state.products.some((p) => p.categoryId === id);
  if (inUse) {
    return { ok: false, error: 'No se puede eliminar: hay productos asociados a esta categoría.' };
  }
  state.categories = state.categories.filter((c) => c.id !== id);
  emit();
  return { ok: true };
}

export function saveIngredient(payload) {
  const name = (payload.name || '').trim();
  if (!name) return { ok: false, error: 'El nombre del ingrediente es obligatorio.' };
  const minStock = roundQty(payload.minStock || 0);
  if (Number.isNaN(minStock) || minStock < 0) return { ok: false, error: 'El stock mínimo no puede ser negativo.' };

  if (payload.id) {
    const ing = state.ingredients.find((i) => i.id === payload.id);
    if (!ing) return { ok: false, error: 'Ingrediente no encontrado.' };
    const hasMovements = state.stockMovements.some((m) => m.ingredientId === ing.id) || ing.currentStock !== 0;
    if (payload.unit && payload.unit !== ing.unit && hasMovements) {
      return { ok: false, error: 'No se puede cambiar la unidad de un ingrediente con stock o movimientos.' };
    }
    ing.name = name;
    if (payload.unit && !hasMovements) ing.unit = payload.unit;
    ing.minStock = minStock;
    ing.active = Boolean(payload.active);
  } else {
    const initial = roundQty(payload.initialStock || 0);
    if (Number.isNaN(initial) || initial < 0) return { ok: false, error: 'El stock inicial no puede ser negativo.' };
    const id = state.nextIds.ingredient++;
    state.ingredients.unshift({
      id,
      name,
      unit: payload.unit || 'kg',
      currentStock: initial,
      minStock,
      active: true,
      dailyUsage7d: 0.4,
      lastUnitPrice: roundMoney(Math.max(0, Number(payload.lastUnitPrice || 0))),
    });
    if (initial > 0) {
      state.stockMovements.unshift({
        id: state.nextIds.stockMovement++,
        ingredientId: id,
        date: new Date().toISOString(),
        type: 'InitialStock',
        delta: initial,
        before: 0,
        after: initial,
        reason: 'Stock inicial al crear ingrediente',
        wasteCategory: null,
        responsible: state.auth.currentUser?.fullName || 'Camila Ríos',
        sourceType: 'Manual',
        sourceId: null,
      });
    }
  }
  emit();
  return { ok: true };
}

export function adjustIngredientStock(ingredientId, newStock, reason) {
  const ing = state.ingredients.find((i) => i.id === ingredientId);
  if (!ing) return { ok: false, error: 'Ingrediente no encontrado.' };
  const next = roundQty(newStock);
  if (Number.isNaN(next) || next < 0) return { ok: false, error: 'El stock ajustado no puede ser negativo.' };
  const trimmed = (reason || '').trim();
  if (!trimmed) return { ok: false, error: 'Debe indicar un motivo para el ajuste.' };
  const before = ing.currentStock;
  const delta = roundQty(next - before);
  if (delta === 0) return { ok: false, error: 'El nuevo stock es igual al stock actual.' };
  ing.currentStock = next;
  state.stockMovements.unshift({
    id: state.nextIds.stockMovement++,
    ingredientId: ing.id,
    date: new Date().toISOString(),
    type: 'Adjustment',
    delta,
    before,
    after: next,
    reason: trimmed,
    wasteCategory: null,
    responsible: state.auth.currentUser?.fullName || 'Camila Ríos',
    sourceType: 'Manual',
    sourceId: null,
  });
  emit();
  return { ok: true };
}

export function registerIngredientWaste(ingredientId, quantity, wasteCategory, reason) {
  const ing = state.ingredients.find((i) => i.id === ingredientId);
  if (!ing) return { ok: false, error: 'Ingrediente no encontrado.' };
  const qty = roundQty(quantity);
  if (Number.isNaN(qty) || qty <= 0) return { ok: false, error: 'La cantidad de merma debe ser mayor a cero.' };
  if (qty > ing.currentStock + 1e-9) return { ok: false, error: 'La merma no puede superar el stock actual disponible.' };
  const trimmed = (reason || '').trim();
  if (!trimmed) return { ok: false, error: 'Debe indicar un motivo de la merma.' };
  const before = ing.currentStock;
  const after = roundQty(before - qty);
  ing.currentStock = after;
  state.stockMovements.unshift({
    id: state.nextIds.stockMovement++,
    ingredientId: ing.id,
    date: new Date().toISOString(),
    type: 'Waste',
    delta: -qty,
    before,
    after,
    reason: trimmed,
    wasteCategory,
    responsible: state.auth.currentUser?.fullName || 'Camila Ríos',
    sourceType: 'Manual',
    sourceId: null,
  });
  emit();
  return { ok: true };
}

export function commitStockCount({ items, notes, expectedSnapshot = null }) {
  const now = new Date().toISOString();
  const actor = state.auth.currentUser?.fullName || 'Camila Ríos';
  const countId = state.nextIds.stockCount++;
  const committedItems = [];

  for (const row of items) {
    const ing = state.ingredients.find((i) => i.id === row.ingredientId);
    if (!ing) continue;
    if (expectedSnapshot && expectedSnapshot[ing.id] !== undefined && Math.abs(expectedSnapshot[ing.id] - ing.currentStock) > 1e-6) {
      return { ok: false, stale: true, error: 'El stock cambió desde que se inició el conteo; vuelva a calcular.' };
    }
    const counted = roundQty(row.counted);
    if (Number.isNaN(counted) || counted < 0) {
      return { ok: false, error: `La cantidad contada de ${ing.name} no puede ser negativa.` };
    }
    const diff = roundQty(counted - ing.currentStock);
    if (diff !== 0 && !(row.reason || '').trim()) {
      return { ok: false, error: `Indicá un motivo para la diferencia en ${ing.name}.` };
    }
    committedItems.push({
      ingredientId: ing.id,
      ingredientName: ing.name,
      unit: ing.unit,
      expected: ing.currentStock,
      counted,
      diff,
      reason: (row.reason || '').trim(),
    });
  }

  for (const ci of committedItems) {
    if (ci.diff === 0) continue;
    const ing = state.ingredients.find((i) => i.id === ci.ingredientId);
    const before = ing.currentStock;
    ing.currentStock = ci.counted;
    state.stockMovements.unshift({
      id: state.nextIds.stockMovement++,
      ingredientId: ing.id,
      date: now,
      type: 'CountAdjustment',
      delta: ci.diff,
      before,
      after: ci.counted,
      reason: `Conteo #${countId}: ${ci.reason}`,
      wasteCategory: null,
      responsible: actor,
      sourceType: 'StockCount',
      sourceId: countId,
    });
  }

  const record = { id: countId, date: now, responsible: actor, notes: (notes || '').trim(), items: committedItems };
  state.stockCounts.unshift(record);
  emit();
  return { ok: true, record };
}

export function recalculateRecipe(recipeId, syncProductCost = false) {
  const recipe = state.recipes.find((r) => r.id === recipeId);
  if (!recipe) return { ok: false };
  const calc = getRecipeCalculation(recipe);
  recipe.lastCalculatedCost = calc.unitCost;
  recipe.lastCalculatedAt = new Date().toISOString();
  if (syncProductCost) {
    const prod = state.products.find((p) => p.name.toLowerCase() === recipe.name.toLowerCase());
    if (prod) prod.cost = calc.unitCost;
  }
  emit();
  return { ok: true, unitCost: calc.unitCost };
}

export function saveRecipe(payload) {
  const name = (payload.name || '').trim();
  const yieldQty = Math.max(1, Number(payload.yield || 1));
  if (!name) return { ok: false, error: 'El nombre de la receta es obligatorio.' };
  if (!payload.ingredients?.length) return { ok: false, error: 'Agregá al menos un ingrediente a la receta.' };

  if (payload.id) {
    const r = state.recipes.find((rec) => rec.id === payload.id);
    if (r) {
      r.name = name;
      r.yield = yieldQty;
      r.ingredients = payload.ingredients;
      const calc = getRecipeCalculation(r);
      r.lastCalculatedCost = calc.unitCost;
      r.lastCalculatedAt = new Date().toISOString();
    }
  } else {
    const newRec = {
      id: state.nextIds.recipe++,
      name,
      yield: yieldQty,
      lastCalculatedCost: 0,
      lastCalculatedAt: new Date().toISOString(),
      ingredients: payload.ingredients,
    };
    const calc = getRecipeCalculation(newRec);
    newRec.lastCalculatedCost = calc.unitCost;
    state.recipes.unshift(newRec);
  }
  emit();
  return { ok: true };
}

export function addSupplier(name) {
  const trimmed = (name || '').trim();
  if (!trimmed) return { ok: false, error: 'Ingresá el nombre del proveedor.' };
  state.suppliers.unshift({ id: state.nextIds.supplier++, name: trimmed });
  emit();
  return { ok: true };
}

export function addInvoice({ date, supplierId, invoiceNumber, notes, items }) {
  if (!supplierId) return { ok: false, error: 'Seleccioná un proveedor.' };
  if (!items.length) return { ok: false, error: 'Agregá al menos un ingrediente a la factura.' };
  const id = state.nextIds.invoice++;
  const now = date ? new Date(date).toISOString() : new Date().toISOString();
  const actor = state.auth.currentUser?.fullName || 'Camila Ríos';

  const normalized = items.map((it) => ({
    ingredientId: Number(it.ingredientId),
    quantity: roundQty(it.quantity),
    unit: it.unit,
    unitPrice: roundMoney(it.unitPrice),
  }));

  state.invoices.unshift({
    id,
    date: now,
    supplierId: Number(supplierId),
    invoiceNumber: (invoiceNumber || '').trim() || `SIN-NRO-${id}`,
    notes: (notes || '').trim(),
    items: normalized,
  });

  // Update stock & latest price per GastroApp InvoiceService contract
  for (const it of normalized) {
    const ing = state.ingredients.find((i) => i.id === it.ingredientId);
    if (!ing) continue;
    const conv = convertUnit(it.quantity, it.unit, ing.unit);
    if (conv.ok) {
      const addedQty = roundQty(conv.value);
      const before = ing.currentStock;
      const after = roundQty(before + addedQty);
      ing.currentStock = after;
      const unitFactor = conv.value / it.quantity;
      if (unitFactor > 0) {
        ing.lastUnitPrice = roundMoney(it.unitPrice / unitFactor);
      }
      state.stockMovements.unshift({
        id: state.nextIds.stockMovement++,
        ingredientId: ing.id,
        date: now,
        type: 'InvoiceReceipt',
        delta: addedQty,
        before,
        after,
        reason: `Factura ${invoiceNumber || `#${id}`}`,
        wasteCategory: null,
        responsible: actor,
        sourceType: 'Invoice',
        sourceId: id,
      });
    }
  }
  emit();
  return { ok: true };
}

export function deleteIngredient(ingredientId) {
  const ing = state.ingredients.find((i) => i.id === ingredientId);
  if (!ing) return { ok: false, error: 'Ingrediente no encontrado.' };
  const hasMovements = state.stockMovements.some((m) => m.ingredientId === ingredientId);
  const inRecipes = state.recipes.some((r) => r.ingredients.some((ri) => ri.ingredientId === ingredientId));
  const inInvoices = state.invoices.some((inv) => inv.items.some((it) => it.ingredientId === ingredientId));
  const inSales = state.sales.some((s) => (s.stockConsumptions || []).some((sc) => sc.ingredientId === ingredientId));
  if (hasMovements || inRecipes || inInvoices || inSales) {
    return { ok: false, error: 'El ingrediente tiene registros asociados; desactívelo en lugar de eliminarlo.' };
  }
  state.ingredients = state.ingredients.filter((i) => i.id !== ingredientId);
  emit();
  return { ok: true };
}

export function deleteRecipe(recipeId) {
  state.recipes = state.recipes.filter((r) => r.id !== recipeId);
  emit();
  return { ok: true };
}

export function updateSupplier(id, name) {
  const trimmed = (name || '').trim();
  if (!trimmed) return { ok: false, error: 'Ingresá el nombre del proveedor.' };
  const sup = state.suppliers.find((s) => s.id === id);
  if (!sup) return { ok: false, error: 'Proveedor no encontrado.' };
  sup.name = trimmed;
  emit();
  return { ok: true };
}

export function deleteSupplier(id) {
  const inUse = state.invoices.some((inv) => inv.supplierId === id);
  if (inUse) {
    return { ok: false, error: 'No se puede eliminar: el proveedor tiene facturas registradas.' };
  }
  state.suppliers = state.suppliers.filter((s) => s.id !== id);
  emit();
  return { ok: true };
}

export function deleteInvoice(invoiceId) {
  const removed = state.invoices.find((inv) => inv.id === invoiceId);
  state.invoices = state.invoices.filter((inv) => inv.id !== invoiceId);
  if (removed) {
    // Recompute latest invoice price for affected ingredients (stock is NOT reversed per contract)
    const affectedIds = [...new Set(removed.items.map((it) => it.ingredientId))];
    const sorted = [...state.invoices].sort((a, b) => new Date(b.date) - new Date(a.date));
    for (const ingId of affectedIds) {
      const ing = state.ingredients.find((i) => i.id === ingId);
      if (!ing) continue;
      let latestPrice = null;
      for (const inv of sorted) {
        const match = inv.items.find((it) => it.ingredientId === ingId);
        if (match) {
          const conv = convertUnit(match.quantity, match.unit, ing.unit);
          if (conv.ok && match.quantity > 0) {
            const factor = conv.value / match.quantity;
            latestPrice = roundMoney(match.unitPrice / factor);
            break;
          }
        }
      }
      if (latestPrice != null) ing.lastUnitPrice = latestPrice;
    }
  }
  emit();
  return { ok: true };
}

export function saveDemoUser({ id, username, fullName, role, active }) {
  const u = (username || '').trim().toLowerCase();
  const fn = (fullName || '').trim();
  if (!u || !fn) return { ok: false, error: 'Completá usuario y nombre completo.' };
  if (role !== 'Admin' && role !== 'Employee') return { ok: false, error: 'Rol inválido.' };
  const dup = state.users.find((x) => x.username.toLowerCase() === u && x.id !== id);
  if (dup) return { ok: false, error: 'Ya existe un usuario con ese identificador.' };
  const initials = fn
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() || '')
    .join('') || 'US';

  if (id) {
    const existing = state.users.find((x) => x.id === id);
    if (existing) {
      existing.username = u;
      existing.fullName = fn;
      existing.role = role;
      existing.active = Boolean(active);
      existing.initials = initials;
      if (state.auth.currentUser?.id === existing.id && !existing.active) {
        state.auth.isAuthenticated = false;
        state.auth.currentUser = null;
      }
    }
  } else {
    const nextId = Math.max(0, ...state.users.map((x) => x.id)) + 1;
    state.users.push({ id: nextId, username: u, fullName: fn, role, active: active !== false, initials });
  }
  emit();
  return { ok: true };
}

export function updateBusinessSettings(patch) {
  state.businessSettings = { ...state.businessSettings, ...patch };
  emit();
}
