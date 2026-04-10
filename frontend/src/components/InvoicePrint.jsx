import React from "react";

const InvoicePrint = React.forwardRef(({ order, qr }, ref) => {
  if (!order) return null;

  return (
    <div ref={ref} style={{ padding: 24, fontFamily: "Arial" }}>
      <h2 style={{ textAlign: "center" }}>HÓA ĐƠN BÁN HÀNG</h2>

      <p><b>Số hóa đơn:</b> {order.order_number}</p>
      <p><b>Ngày:</b> {new Date().toLocaleString("vi-VN")}</p>

      <hr />

      <table width="100%" border="1" cellPadding="6" style={{ borderCollapse: "collapse" }}>
        <thead>
          <tr>
            <th>Sản phẩm</th>
            <th>SL</th>
            <th>Đơn giá</th>
            <th>Thành tiền</th>
          </tr>
        </thead>
        <tbody>
          {order.details.map((i, idx) => (
            <tr key={idx}>
              <td>{i.name}</td>
              <td align="center">{i.quantity}</td>
              <td align="right">{i.price.toLocaleString()} đ</td>
              <td align="right">
                {(i.quantity * i.price).toLocaleString()} đ
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <h3 style={{ textAlign: "right", marginTop: 12 }}>
        Tổng cộng: {order.total.toLocaleString()} đ
      </h3>

      {/* QR PAYOS */}
      {qr && (
        <>
          <hr />
          <p style={{ textAlign: "center" }}>Quét mã để thanh toán</p>
          <div style={{ textAlign: "center" }}>
            <img src={qr} alt="QR PayOS" width={180} />
          </div>
        </>
      )}

      <p style={{ textAlign: "center", marginTop: 16 }}>
        Xin cảm ơn quý khách!
      </p>
    </div>
  );
});

export default InvoicePrint;
