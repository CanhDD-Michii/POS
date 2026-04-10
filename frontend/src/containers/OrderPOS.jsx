import { useState, useEffect, useCallback } from "react";
import { Button, Space, Card, message, Typography, Modal, Divider } from "antd";
import {
  ShoppingCartOutlined,
  CreditCardOutlined,
  DollarOutlined,
  UserOutlined,
  GiftOutlined,
} from "@ant-design/icons";

import apiClient from "../core/api";
import ProductSelectModal from "../components/ProductSelectModal";
import CartTable from "../components/CartTable";
import usePosCalculator from "../hooks/usePosCalculator";
import OnlinePaymentModal from "../components/OnlinePaymentModal";
import CustomerSelectModal from "../components/CustomerSelectModal";
import PromotionSelectModal from "../components/PromotionSelectModal";
import { fetchAllPaymentMethods, resolvePaymentMethodId } from "../utils/paymentMethods";

import "../styles/OrderPOS.css";

const { Title, Text } = Typography;

/**
 * POS checkout: order header (customer, line items, voucher/promotion), payment, optional print.
 */
function OrderPOS() {
  const [cart, setCart] = useState([]);
  const [customers, setCustomers] = useState([]);
  const [promotions, setPromotions] = useState([]);
  const [paymentMethods, setPaymentMethods] = useState([]);

  const [selectedCustomer, setSelectedCustomer] = useState(undefined);
  const [selectedPromotion, setSelectedPromotion] = useState(undefined);

  const [customerModalOpen, setCustomerModalOpen] = useState(false);
  const [promotionModalOpen, setPromotionModalOpen] = useState(false);
  const [modalProduct, setModalProduct] = useState(false);

  const [paymentModalVisible, setPaymentModalVisible] = useState(false);
  const [onlineModalOpen, setOnlineModalOpen] = useState(false);
  const [onlinePayment, setOnlinePayment] = useState(null);
  const [onlineLoading, setOnlineLoading] = useState(false);

  const [invoicePreview, setInvoicePreview] = useState(null);
  const [printConfirmOpen, setPrintConfirmOpen] = useState(false);

  const { subtotal, discountPercent, discount, total } = usePosCalculator(
    cart,
    selectedPromotion,
    promotions
  );

  const loadMasters = useCallback(async () => {
    try {
      const [cus, promo, pm] = await Promise.all([
        apiClient.get("/customers", { params: { page: 1, limit: 200 } }),
        apiClient.get("/promotions", { params: { page: 1, limit: 200 } }),
        fetchAllPaymentMethods(),
      ]);
      setCustomers(cus.data.data || []);
      setPromotions(promo.data.data || []);
      setPaymentMethods(pm);
    } catch (err) {
      console.error(err);
      message.error("Lỗi tải danh mục POS");
    }
  }, []);

  useEffect(() => {
    loadMasters();
  }, [loadMasters]);

  const generateOrderNumber = () => {
    const d = new Date();
    return `HD-${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(
      d.getDate()
    ).padStart(2, "0")}-${String(d.getHours()).padStart(2, "0")}${String(
      d.getMinutes()
    ).padStart(2, "0")}${String(d.getSeconds()).padStart(2, "0")}`;
  };

  const addToCart = (product) => {
    setCart((prev) => {
      const exist = prev.find((p) => p.product_id === product.product_id);
      if (exist) {
        if (product.stock && exist.quantity + 1 > product.stock) {
          message.warning("Vượt quá tồn kho");
          return prev;
        }
        return prev.map((p) =>
          p.product_id === product.product_id ? { ...p, quantity: exist.quantity + 1 } : p
        );
      }
      return [...prev, { ...product, quantity: 1 }];
    });
  };

  const buildInvoicePreview = () => {
    const cust = customers.find((c) => c.customer_id === selectedCustomer);
    const promo = promotions.find((p) => p.promotion_id === selectedPromotion);
    return {
      order_number: generateOrderNumber(),
      created_at: new Date(),
      customer_name: cust?.name || "Khách lẻ",
      voucher_name: promo?.name || null,
      promotion_name: promo?.name || null,
      items: cart.map((p) => ({
        name: p.name,
        quantity: p.quantity,
        price: p.price,
        total: p.quantity * p.price,
      })),
      subtotal,
      discount,
      discountPercent,
      total,
    };
  };

  const postOrder = async (paymentMethodId, status) => {
    const order_number = generateOrderNumber();
    await apiClient.post("/orders", {
      order_number,
      customer_id: selectedCustomer,
      promotion_id: selectedPromotion,
      payment_method_id: paymentMethodId,
      status,
      details: cart.map((p) => ({
        product_id: p.product_id,
        quantity: p.quantity,
        price: p.price,
      })),
    });
    return order_number;
  };

  /** Cash / default counter payment */
  const handleCashCheckout = async () => {
    const cashId = resolvePaymentMethodId(paymentMethods, "cash", "tiền mặt", "tm", "mat");
    if (cashId == null) {
      message.error("Chưa cấu hình phương thức tiền mặt trong hệ thống");
      return;
    }
    try {
      await postOrder(cashId, "completed");
      message.success("Thanh toán tiền mặt thành công!");
      resetCart();
    } catch (err) {
      console.error(err);
      message.error("Không thể tạo hóa đơn tiền mặt");
    }
  };

  /** Online gateway (e.g. PayOS) — creates pending order then payment link */
  const handleOnlineCheckout = async () => {
    const onlineId = resolvePaymentMethodId(
      paymentMethods,
      "payos",
      "online",
      "chuyển khoản",
      "ck"
    );
    if (onlineId == null) {
      message.error("Chưa cấu hình phương thức thanh toán online");
      return;
    }
    try {
      setOnlineLoading(true);
      const order_number = await postOrder(onlineId, "pending");

      await apiClient.post("/payments/payos", {
        orderNumber: order_number,
        amount: total,
        description: `Pay-${order_number}`.substring(0, 25),
        type: "order",
        returnUrl: `${window.location.origin}/orders`,
        cancelUrl: `${window.location.origin}/orders`,
      });

      const latestRes = await apiClient.get(`/payments/latest?orderNumber=${order_number}`);
      let p = latestRes.data?.data;
      if (!p) {
        message.error("Không tìm thấy thông tin thanh toán");
        return;
      }
      const rawQR = p.qr_base64 || p.qrCode || p.data?.qrCode || null;
      p.qrCode = rawQR;
      setOnlinePayment(p);
      setOnlineModalOpen(true);
      message.success("Đã tạo yêu cầu thanh toán online");
      resetCart();
    } catch (err) {
      console.error(err);
      message.error("Không thể tạo thanh toán online");
    } finally {
      setOnlineLoading(false);
    }
  };

  const resetCart = () => {
    setCart([]);
    setSelectedCustomer(undefined);
    setSelectedPromotion(undefined);
  };

  const handleCheckout = () => {
    if (!cart.length) return message.warning("Giỏ hàng trống!");
    if (!paymentMethods.length) {
      message.warning("Đang tải phương thức thanh toán…");
      return;
    }
    setInvoicePreview(buildInvoicePreview());
    setPrintConfirmOpen(true);
  };

  const proceedWithPayment = (type) => {
    setPaymentModalVisible(false);
    if (type === "cash") handleCashCheckout();
    if (type === "online") handleOnlineCheckout();
  };

  const refreshPaymentStatus = async (payCode) => {
    if (!payCode) return;
    try {
      const res = await apiClient.get(`/payments/${payCode}`);
      const updated = res.data.data;
      setOnlinePayment((prev) => ({ ...prev, status: updated.status }));
      if (updated.status === "completed") message.success("Thanh toán thành công!");
    } catch (err) {
      console.error(err);
      message.error("Không thể cập nhật trạng thái thanh toán");
    }
  };

  const clearCustomerAndPromotion = () => {
    setSelectedCustomer(undefined);
    setSelectedPromotion(undefined);
    message.info("Đã hủy khách hàng và voucher");
  };

  return (
    <div className="pos-container">
      <div className="pos-header">
        <Title level={3}>POS — Tạo đơn</Title>
        <Text type="secondary">Khách hàng · Sản phẩm · Voucher (khuyến mãi)</Text>
      </div>

      <Card size="small" title="1. Thông tin khách" style={{ marginBottom: 12 }}>
        <Space wrap>
          <Button size="large" icon={<UserOutlined />} onClick={() => setCustomerModalOpen(true)}>
            {selectedCustomer
              ? customers.find((c) => c.customer_id === selectedCustomer)?.name
              : "Khách lẻ — chọn"}
          </Button>
          {(selectedCustomer || selectedPromotion) && (
            <Button danger size="large" onClick={clearCustomerAndPromotion}>
              Hủy khách / voucher
            </Button>
          )}
        </Space>
      </Card>

      <Card size="small" title="2. Sản phẩm" style={{ marginBottom: 12 }}>
        <Button size="large" icon={<ShoppingCartOutlined />} onClick={() => setModalProduct(true)}>
          Thêm sản phẩm
        </Button>
      </Card>

      <Card size="small" title="3. Voucher (khuyến mãi)" style={{ marginBottom: 12 }}>
        <Button size="large" icon={<GiftOutlined />} onClick={() => setPromotionModalOpen(true)}>
          {selectedPromotion
            ? promotions.find((p) => p.promotion_id === selectedPromotion)?.name
            : "Chọn voucher"}
        </Button>
      </Card>

      <Divider />

      <div className="pos-cart-wrapper">
        <CartTable cart={cart} setCart={setCart} />
      </div>

      <Card className="pos-summary">
        <div className="pos-summary-row">
          <span>Tạm tính:</span>
          <span>{subtotal.toLocaleString()} đ</span>
        </div>
        <div className="pos-summary-row">
          <span>Giảm giá ({discountPercent || 0}%):</span>
          <span>{discount.toLocaleString()} đ</span>
        </div>
        <div className="pos-summary-total">
          <span>Tổng cộng:</span>
          <span>{total.toLocaleString()} đ</span>
        </div>

        <Button type="primary" size="large" block loading={onlineLoading} onClick={handleCheckout}>
          Thanh toán
        </Button>
      </Card>

      <Modal
        title="Chọn phương thức thanh toán"
        open={paymentModalVisible}
        onCancel={() => setPaymentModalVisible(false)}
        footer={null}
        destroyOnClose
        width={400}
      >
        <Space direction="vertical" style={{ width: "100%" }} size="middle">
          <Button size="large" block icon={<DollarOutlined />} onClick={() => proceedWithPayment("cash")}>
            Thanh toán tiền mặt
          </Button>
          <Button
            type="primary"
            size="large"
            block
            icon={<CreditCardOutlined />}
            loading={onlineLoading}
            onClick={() => proceedWithPayment("online")}
          >
            Thanh toán online
          </Button>
        </Space>
      </Modal>

      <ProductSelectModal
        visible={modalProduct}
        onClose={() => setModalProduct(false)}
        onSelect={addToCart}
      />

      <OnlinePaymentModal
        open={onlineModalOpen}
        data={onlinePayment}
        loading={onlineLoading}
        onClose={() => setOnlineModalOpen(false)}
        onRefresh={refreshPaymentStatus}
      />

      <CustomerSelectModal
        open={customerModalOpen}
        onClose={() => setCustomerModalOpen(false)}
        onSelect={(c) => setSelectedCustomer(c.customer_id)}
      />
      <PromotionSelectModal
        open={promotionModalOpen}
        onClose={() => setPromotionModalOpen(false)}
        onSelect={(p) => setSelectedPromotion(p.promotion_id)}
      />

      <Modal
        open={printConfirmOpen}
        title="Xác nhận in & thanh toán"
        onCancel={() => setPrintConfirmOpen(false)}
        footer={null}
        width={520}
      >
        {invoicePreview && (
          <>
            <div className="print-area">
              <h3 style={{ textAlign: "center" }}>HÓA ĐƠN</h3>
              <div>Mã HĐ: {invoicePreview.order_number}</div>
              <div>Ngày: {invoicePreview.created_at.toLocaleString("vi-VN")}</div>
              <div>Khách hàng: {invoicePreview.customer_name}</div>
              {invoicePreview.voucher_name && <div>Voucher: {invoicePreview.voucher_name}</div>}
              <hr />
              {invoicePreview.items.map((i, idx) => (
                <div key={idx} style={{ display: "flex", justifyContent: "space-between" }}>
                  <span>
                    {i.name} x{i.quantity}
                  </span>
                  <span>{i.total.toLocaleString()} đ</span>
                </div>
              ))}
              <hr />
              <div>Tạm tính: {invoicePreview.subtotal.toLocaleString()} đ</div>
              <div>
                Giảm ({invoicePreview.discountPercent}%): {invoicePreview.discount.toLocaleString()} đ
              </div>
              <h4>Tổng cộng: {invoicePreview.total.toLocaleString()} đ</h4>
            </div>

            <Space style={{ marginTop: 16, width: "100%" }} direction="vertical">
              <Button
                type="primary"
                onClick={() => {
                  window.print();
                  setPrintConfirmOpen(false);
                  setPaymentModalVisible(true);
                }}
              >
                In &amp; thanh toán
              </Button>
              <Button
                onClick={() => {
                  setPrintConfirmOpen(false);
                  setPaymentModalVisible(true);
                }}
              >
                Bỏ qua in — thanh toán
              </Button>
            </Space>
          </>
        )}
      </Modal>
    </div>
  );
}

export default OrderPOS;
