import apiClient from "../core/api";

/**
 * Load all payment methods (handles paginated API).
 */
export async function fetchAllPaymentMethods() {
  const out = [];
  let page = 1;
  const limit = 100;
  for (;;) {
    const res = await apiClient.get("/payment-methods", { params: { page, limit } });
    const items = res.data?.data || [];
    const total = res.data?.pagination?.total ?? items.length;
    out.push(...items);
    if (out.length >= total || items.length === 0) break;
    page += 1;
  }
  return out;
}

/**
 * Pick payment_method_id by matching `code` or substring of `name` (case-insensitive).
 */
export function resolvePaymentMethodId(methods, ...hints) {
  const want = hints.map((h) => String(h).toLowerCase());
  for (const m of methods) {
    const code = (m.code || "").toLowerCase();
    const name = (m.name || "").toLowerCase();
    for (const h of want) {
      if (code === h || name.includes(h)) return m.payment_method_id;
    }
  }
  return methods[0]?.payment_method_id;
}
