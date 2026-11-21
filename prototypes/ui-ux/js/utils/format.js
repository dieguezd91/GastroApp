const arsFormatter = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: 'ARS',
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
});

const arsExactFormatter = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: 'ARS',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const numFormatter = new Intl.NumberFormat('es-AR', {
  minimumFractionDigits: 0,
  maximumFractionDigits: 3,
});

const dateTimeFormatter = new Intl.DateTimeFormat('es-AR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const timeFormatter = new Intl.DateTimeFormat('es-AR', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const dateFormatter = new Intl.DateTimeFormat('es-AR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
});

export function formatARS(amount, alwaysDecimals = false) {
  const n = Number(amount || 0);
  const rounded = Math.round(n * 100) / 100;
  if (alwaysDecimals || Math.abs(rounded % 1) > 0.001) {
    return arsExactFormatter.format(rounded);
  }
  return arsFormatter.format(rounded);
}

export function formatNum(value) {
  return numFormatter.format(Number(value || 0));
}

export function formatPct(value) {
  return `${numFormatter.format(Number(value || 0))}%`;
}

export function formatDateTime(iso) {
  if (!iso) return '—';
  return dateTimeFormatter.format(new Date(iso));
}

export function formatTime(iso) {
  if (!iso) return '—';
  return timeFormatter.format(new Date(iso));
}

export function formatDate(iso) {
  if (!iso) return '—';
  return dateFormatter.format(new Date(iso));
}

export function escapeHtml(str) {
  return String(str ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function roundMoney(val) {
  return Math.round((Number(val) + Number.EPSILON) * 100) / 100;
}

export function roundQty(val) {
  return Math.round((Number(val) + Number.EPSILON) * 10000) / 10000;
}

/**
 * Mirrors Services/UnitConverter.cs exactly:
 * 1 kg = 1000 gr, 1 lt = 1000 ml, unidad <-> unidad.
 * No cross-category weight/volume conversion.
 */
export function convertUnit(quantity, fromUnit, toUnit) {
  if (fromUnit === toUnit) return { ok: true, value: quantity };
  if (fromUnit === 'kg' && toUnit === 'gr') return { ok: true, value: quantity * 1000 };
  if (fromUnit === 'gr' && toUnit === 'kg') return { ok: true, value: quantity / 1000 };
  if (fromUnit === 'lt' && toUnit === 'ml') return { ok: true, value: quantity * 1000 };
  if (fromUnit === 'ml' && toUnit === 'lt') return { ok: true, value: quantity / 1000 };
  return { ok: false, value: 0 };
}

export function getCompatibleUnits(baseUnit) {
  if (baseUnit === 'kg' || baseUnit === 'gr') return ['gr', 'kg'];
  if (baseUnit === 'lt' || baseUnit === 'ml') return ['ml', 'lt'];
  return [baseUnit || 'unidad'];
}

export function getDefaultRecipeUnit(baseUnit) {
  if (baseUnit === 'kg') return 'gr';
  if (baseUnit === 'lt') return 'ml';
  return baseUnit || 'unidad';
}

export function formatQtyUnit(qty, unit) {
  return `${formatNum(qty)} ${unit}`;
}
