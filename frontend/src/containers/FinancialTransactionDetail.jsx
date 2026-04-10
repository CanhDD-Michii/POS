// src/components/FinancialTransactionDetail.jsx
import { useEffect, useState } from "react";
import { Drawer, Descriptions, Tag, Divider, message } from "antd";
import apiClient from "../core/api";

const TYPE_COLORS = {
  income: "green",
  expense: "red",
  other: "default",
};

function fmtCurrency(v) {
  return `${Number(v || 0).toLocaleString("vi-VN")} ₫`;
}
function fmtDate(d) {
  const t = d ? new Date(d) : null;
  return t && !isNaN(t) ? t.toLocaleDateString("vi-VN") : "—";
}
function fmtDateTime(d) {
  const t = d ? new Date(d) : null;
  return t && !isNaN(t)
    ? t.toLocaleString("vi-VN")
    : "—";
}

export default function FinancialTransactionDetail({ open, id, onClose }) {
  const [data, setData] = useState(null);

  useEffect(() => {
    if (!open || !id) return;
    (async () => {
      try {
        const res = await apiClient.get(`/financial-transactions/${id}`);
        setData(res.data?.data || null);
      } catch {
        message.error("Không tải được chi tiết giao dịch");
      }
    })();
  }, [open, id]);

  return (
    <Drawer
      width={640}
      open={open}
      onClose={onClose}
      title="📄 Chi tiết giao dịch tài chính"
    >
      {!data ? (
        "Đang tải..."
      ) : (
        <>
          {/* ===== THÔNG TIN GIAO DỊCH ===== */}
          <Divider orientation="left">Thông tin giao dịch</Divider>
          <Descriptions bordered size="small" column={2}>
            <Descriptions.Item label="Mã giao dịch" span={2}>
              {data.transaction_id}
            </Descriptions.Item>

            <Descriptions.Item label="Loại">
              <Tag color={TYPE_COLORS[data.type] || "default"}>
                {data.type}
              </Tag>
            </Descriptions.Item>

            <Descriptions.Item label="Trạng thái">
              {data.status || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Số tiền">
              {fmtCurrency(data.amount)}
            </Descriptions.Item>

            <Descriptions.Item label="Ngày giao dịch">
              {fmtDate(data.transaction_date)}
            </Descriptions.Item>

            <Descriptions.Item label="Phương thức thanh toán" span={2}>
              {data.payment_method_name || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Ghi chú" span={2}>
              {data.note || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Mã chứng từ gốc" span={2}>
              {data.original_document_number || "—"}
            </Descriptions.Item>
          </Descriptions>

          {/* ===== ĐỐI TƯỢNG GIAO DỊCH ===== */}
          <Divider orientation="left">Đối tượng giao dịch</Divider>
          <Descriptions bordered size="small" column={2}>
            <Descriptions.Item label="Khách hàng">
              {data.customer_name || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Nhà cung cấp">
              {data.supplier_name || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Người giao dịch" span={2}>
              {data.payer_receiver_name || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Số điện thoại">
              {data.payer_receiver_phone || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Địa chỉ" span={2}>
              {data.payer_receiver_address || "—"}
            </Descriptions.Item>
          </Descriptions>

          {/* ===== LIÊN KẾT CHỨNG TỪ ===== */}
          <Divider orientation="left">Liên kết chứng từ</Divider>
          <Descriptions bordered size="small" column={2}>
            <Descriptions.Item label="Đơn hàng">
              {data.related_order_id
                ? `#${data.related_order_id}`
                : "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Phiếu nhập">
              {data.related_purchase_id
                ? `#${data.related_purchase_id}`
                : "—"}
            </Descriptions.Item>
          </Descriptions>

          {/* ===== HỆ THỐNG ===== */}
          <Divider orientation="left">Thông tin hệ thống</Divider>
          <Descriptions bordered size="small" column={2}>
            <Descriptions.Item label="Nhân viên tạo">
              {data.employee_name || "—"}
            </Descriptions.Item>

            <Descriptions.Item label="Thời điểm tạo">
              {fmtDateTime(data.created_at)}
            </Descriptions.Item>
          </Descriptions>
        </>
      )}
    </Drawer>
  );
}
