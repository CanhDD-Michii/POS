import { useEffect, useState } from "react";
import { Descriptions, Table, Button, message, Card } from "antd";
import { useNavigate, useParams } from "react-router-dom";
import apiClient from "../core/api";
import moment from "moment"; // eslint-disable-line no-unused-vars

const invoiceStyle = `
@media print {
  body * {
    visibility: hidden;
  }
  #pos-invoice, #pos-invoice * {
    visibility: visible;
  }
  #pos-invoice {
    position: absolute;
    left: 0;
    top: 0;
    width: 100%;
  }
  .no-print {
    display: none !important;
  }
}

#pos-invoice {
  font-family: 'Segoe UI', Arial, sans-serif;
  font-size: 14px;
  max-width: 420px;
  margin: auto;
}
.pos-row {
  display: flex;
  justify-content: space-between;
}
.pos-center {
  text-align: center;
}
.pos-divider {
  border-top: 1px dashed #999;
  margin: 8px 0;
}
`;

function OrderDetail() {
  const { id } = useParams(); // id chính là order_id hoặc order_number tùy API
  const navigate = useNavigate();
  const [order, setOrder] = useState(null);
  const [loading, setLoading] = useState(true); // eslint-disable-line no-unused-vars

  const fetchDetail = async () => {
    try {
      const res = await apiClient.get(`/orders/${id}`);
      setOrder(res.data.data);
    } catch (err) {
      message.error("Không tải được chi tiết hóa đơn");
      console.error(err);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchDetail();
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  // const downloadInvoice = async () => {
  //   try {
  //     const response = await apiClient.get(`/orders/${id}/invoice`, {
  //       responseType: "blob",
  //     });
  //     const blob = new Blob([response.data], { type: "application/pdf" });
  //     const url = window.URL.createObjectURL(blob);
  //     const link = document.createElement("a");
  //     link.href = url;
  //     link.download = `invoice-${order.order_number}.pdf`;
  //     document.body.appendChild(link);
  //     link.click();
  //     link.remove();
  //     window.URL.revokeObjectURL(url);
  //   } catch (err) {
  //     console.error(err);
  //     message.error("Không thể tải hóa đơn");
  //   }
  // };

  if (!order) return null;

  // const columns = [
  //   { title: "Sản phẩm", dataIndex: "product_name" },
  //   { title: "Số lượng", dataIndex: "quantity" },
  //   {
  //     title: "Đơn giá",
  //     dataIndex: "price",
  //     render: (v) => `${Number(v).toLocaleString()} đ`,
  //   },
  //   {
  //     title: "Thành tiền",
  //     render: (_, r) => `${(r.quantity * r.price).toLocaleString()} đ`,
  //   },
  // ];

  // const total = order.details?.reduce(
  //   (sum, i) => sum + i.quantity * i.price,
  //   0
  // );

  return (
    <>
      <style>{invoiceStyle}</style>

      {/* NÚT ĐIỀU KHIỂN */}
      <div className="no-print" style={{ marginBottom: 12 }}>
        <Button onClick={() => navigate("/orders")}>← Quay lại</Button>
        <Button
          type="primary"
          style={{ marginLeft: 8 }}
          onClick={() => window.print()}
        >
          🖨 In hóa đơn
        </Button>
      </div>

      {/* ===== POS INVOICE ===== */}
      <div id="pos-invoice">
        <div className="pos-center">
          <h3>🐾 PET CLINIC</h3>
          <div>Phòng khám thú y</div>
        </div>

        <div className="pos-divider" />

        <div>
          Mã HĐ: <b>{order.order_number}</b>
        </div>
        <div>Ngày: {new Date(order.order_date).toLocaleString("vi-VN")}</div>
        <div>Khách hàng: {order.customer_name || "Khách lẻ"}</div>

        <div className="pos-divider" />

        {/* DANH SÁCH SẢN PHẨM */}
        {order.details.map((i, idx) => (
          <div key={idx} style={{ marginBottom: 4 }}>
            <div>
              {i.product_name} x{i.quantity}
            </div>
            <div className="pos-row">
              <span></span>
              <span>{(i.quantity * i.price).toLocaleString()} đ</span>
            </div>
          </div>
        ))}

        <div className="pos-divider" />

        <div className="pos-row">
          <span>Tạm tính</span>
          <span>
            {order.details
              .reduce((s, i) => s + i.quantity * i.price, 0)
              .toLocaleString()}{" "}
            đ
          </span>
        </div>

        {order.discount_amount > 0 && (
          <div className="pos-row">
            <span>Giảm giá</span>
            <span>-{order.discount_amount.toLocaleString()} đ</span>
          </div>
        )}

        <div className="pos-row" style={{ fontWeight: 700, marginTop: 6 }}>
          <span>TỔNG CỘNG</span>
          <span>{Number(order.total_amount).toLocaleString()} đ</span>
        </div>

        {/* QR PAYOS */}
        {order.payment_method === "PayOS" && order.qrCode && (
          <>
            <div className="pos-divider" />
            <div className="pos-center">
              <div>Quét mã để thanh toán</div>
              <img
                src={`data:image/png;base64,${order.qrCode}`}
                alt="QR"
                style={{ width: 160, marginTop: 8 }}
              />
            </div>
          </>
        )}

        <div className="pos-divider" />

        <div className="pos-center">
          <div>Cảm ơn quý khách!</div>
          <div>Hẹn gặp lại 🐶🐱</div>
        </div>
      </div>
    </>
  );
}

export default OrderDetail;
