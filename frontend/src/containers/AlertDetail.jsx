import { Descriptions, Modal, Tag } from "antd";

// Map icon theo type
const typeIcon = {
  low_stock: "⚠️",
  over_stock: "🔥",
  promotion_expired: "🧊",
  ai_prediction: "📌",
};

const severityColor = {
  high: "red",
  medium: "orange",
  low: "gold",
};

export default function AlertDetail({ open, onClose, record }) {
  if (!record) return null;

  return (
    <Modal
      open={open}
      onCancel={onClose}
      onOk={onClose}
      okText="Đóng"
      title={
        <span>
          {typeIcon[record.type] || "🔔"} Chi tiết cảnh báo
        </span>
      }
      width={720}
    >
      <Descriptions bordered column={1}>
        <Descriptions.Item label="Loại">
          {typeIcon[record.type] || "🔔"} {record.type || "—"}
        </Descriptions.Item>
        <Descriptions.Item label="Thông điệp">
          {record.message || "—"}
        </Descriptions.Item>
        <Descriptions.Item label="Mức độ">
          <Tag color={severityColor[record.severity] || "default"}>
            {record.severity || "—"}
          </Tag>
        </Descriptions.Item>
        <Descriptions.Item label="Sản phẩm liên quan">
          {record.product_name || "—"}
        </Descriptions.Item>
        <Descriptions.Item label="Trạng thái">
          {record.is_resolved ? <Tag color="green">Đã xử lý</Tag> : <Tag color="red">Chưa xử lý</Tag>}
        </Descriptions.Item>
        {/* API hiện tại của bạn không trả created_at / updated_at trong LIST/DETAIL → không hiển thị để tránh dữ liệu rỗng */}
      </Descriptions>
    </Modal>
  );
}
