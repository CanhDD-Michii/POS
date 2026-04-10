import { Modal, Button, Space, Typography, Tag, Alert } from "antd";
import { ReloadOutlined, CopyOutlined, LinkOutlined } from "@ant-design/icons";

const { Text, Paragraph } = Typography;

export default function OnlinePaymentModal({
  open,
  data,
  loading,
  onClose,
  onRefresh,
}) {
  if (!data) return null;

  const isCompleted = data.status === "completed";
  const qrSrc = data.qrCode ? `${data.qrCode}` : null;

  return (
    <Modal
      open={open}
      onCancel={onClose}
      title="Thanh toán PayOS"
      footer={
        <Space>
          <Button
            icon={<CopyOutlined />}
            disabled={!data.checkout_url}
            onClick={() => navigator.clipboard.writeText(data.checkout_url)}
          >
            Sao chép link
          </Button>

          <Button
            type="primary"
            icon={<LinkOutlined />}
            disabled={!data.checkout_url}
            onClick={() => window.open(data.checkout_url, "_blank")}
          >
            Mở link
          </Button>

          <Button
            icon={<ReloadOutlined />}
            loading={loading}
            onClick={() => onRefresh(data.pay_code)}
          >
            Cập nhật
          </Button>
        </Space>
      }
    >
      <Alert
        type={isCompleted ? "success" : "info"}
        message={
          isCompleted
            ? "Thanh toán hoàn tất."
            : "Quét QR hoặc mở link để thanh toán."
        }
        showIcon
        style={{ marginBottom: 16 }}
      />

      <div>
        <Text strong>Mã đơn:</Text> <Text code>{data.order_number || data.purchase_number}</Text>
      </div>

      <div>
        <Text strong>Số tiền:</Text>{" "}
        <Text>{Number(data.amount).toLocaleString("vi-VN")} đ</Text>
      </div>

      <div>
        <Text strong>Trạng thái:</Text>{" "}
        <Tag color={isCompleted ? "green" : "orange"}>{data.status}</Tag>
      </div>

      {qrSrc ? (
        <div style={{ textAlign: "center", marginTop: 16 }}>
          <img src={qrSrc} alt="QR PayOS" style={{ width: 260 }} />
          <Paragraph type="secondary">Quét QR để thanh toán</Paragraph>
        </div>
      ) : (
        <Paragraph>Không tìm thấy QR</Paragraph>
      )}
    </Modal>
  );
}
