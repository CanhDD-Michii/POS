export default function usePosCalculator(cart, selectedPromotionId, promotionsList = []) {
  const subtotal = cart.reduce((s, i) => s + Number(i.price || 0) * Number(i.quantity || 0), 0);

  let discountPercent = 0;
  if (selectedPromotionId && promotionsList?.length) {
    const found = promotionsList.find((p) => p.promotion_id === selectedPromotionId);
    if (found?.discount_percent) discountPercent = Number(found.discount_percent) || 0;
  }

  const discount = Math.floor((subtotal * discountPercent) / 100);
  const total = Math.max(0, subtotal - discount);

  return { subtotal, discountPercent, discount, total };
}
