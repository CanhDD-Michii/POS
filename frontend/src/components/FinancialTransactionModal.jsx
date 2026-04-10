import { useEffect, useState } from "react";
import {
  Modal,
  Form,
  Input,
  InputNumber,
  DatePicker,
  Select,
  message,
  Row,
  Col,
  Divider,
} from "antd";
import dayjs from "dayjs";
import apiClient from "../core/api";

export default function FinancialTransactionModal({
  open,
  onClose,
  onSuccess,
  editing,
}) {
  const [form] = Form.useForm();
  const [pmList, setPmList] = useState([]);
  const isEdit = !!editing;

  useEffect(() => {
    apiClient.get("/payment-methods?page=1&limit=100").then((res) => {
      setPmList(res.data?.data || []);
    });
  }, []);

  useEffect(() => {
    if (isEdit) {
      form.setFieldsValue({
        ...editing,
        transaction_date: editing.transaction_date
          ? dayjs(editing.transaction_date)
          : null,
      });
    } else {
      form.resetFields();
      form.setFieldsValue({
        transaction_date: dayjs(),
        type: "income",
        status: "completed",
      });
    }
  }, [isEdit, editing]); // eslint-disable-line

  const submit = async () => {
    try {
      const v = await form.validateFields();
      const payload = {
        ...v,
        amount: Number(v.amount || 0),
        transaction_date: v.transaction_date?.format("YYYY-MM-DD"),
      };

      if (isEdit) {
        await apiClient.put(
          `/financial-transactions/${editing.transaction_id}`,
          payload
        );
        message.success("Cập nhật giao dịch thành công");
      } else {
        await apiClient.post("/financial-transactions", payload);
        message.success("Thêm giao dịch thành công");
      }

      onSuccess();
    } catch (err) {
      if (err?.errorFields) return;
      console.error(err);
      message.error("Không thể lưu giao dịch");
    }
  };

  return (
    <Modal
      open={open}
      title={isEdit ? "✏️ Sửa giao dịch tài chính" : "➕ Thêm giao dịch tài chính"}
      onCancel={onClose}
      onOk={submit}
      okText="Lưu"
      destroyOnClose
      width={760}
    >
      <Form layout="vertical" form={form} preserve>
        {/* ===== NHÓM 1: THÔNG TIN CHUNG ===== */}
        <Divider orientation="left">Thông tin giao dịch</Divider>

        <Row gutter={16}>
          <Col span={12}>
            <Form.Item
              name="type"
              label="Loại giao dịch"
              rules={[{ required: true }]}
            >
              <Select
                options={[
                  { label: "Thu (Income)", value: "income" },
                  { label: "Chi (Expense)", value: "expense" },
                  { label: "Khác (Other)", value: "other" },
                ]}
              />
            </Form.Item>
          </Col>

          <Col span={12}>
            <Form.Item
              name="status"
              label="Trạng thái"
              rules={[{ required: true }]}
            >
              <Select
                options={[
                  { label: "Hoàn tất", value: "completed" },
                  { label: "Chờ xử lý", value: "pending" },
                  { label: "Hủy", value: "cancelled" },
                ]}
              />
            </Form.Item>
          </Col>

          <Col span={12}>
            <Form.Item
              name="amount"
              label="Số tiền (₫)"
              rules={[{ required: true }]}
            >
              <InputNumber
                min={0}
                style={{ width: "100%" }}
                placeholder="VD: 1.200.000"
                formatter={(value) =>
                  value
                    ? `${value}`.replace(/\B(?=(\d{3})+(?!\d))/g, ".")
                    : ""
                }
                parser={(value) => value.replace(/\./g, "")}
              />
            </Form.Item>
          </Col>

          <Col span={12}>
            <Form.Item
              name="transaction_date"
              label="Ngày giao dịch"
              rules={[{ required: true }]}
            >
              <DatePicker style={{ width: "100%" }} />
            </Form.Item>
          </Col>
        </Row>

        {/* ===== NHÓM 2: THANH TOÁN & CHỨNG TỪ ===== */}
        <Divider orientation="left">Chứng từ & thanh toán</Divider>

        <Row gutter={16}>
          <Col span={12}>
            <Form.Item name="payment_method_id" label="Phương thức thanh toán">
              <Select
                allowClear
                placeholder="Chọn phương thức"
                options={pmList.map((p) => ({
                  label: p.name,
                  value: p.payment_method_id,
                }))}
              />
            </Form.Item>
          </Col>

          <Col span={12}>
            <Form.Item name="original_document_number" label="Mã chứng từ">
              <Input placeholder="VD: HD-001, PN-002..." />
            </Form.Item>
          </Col>

          <Col span={12}>
            <Form.Item name="related_order_id" label="Mã đơn hàng">
              <InputNumber min={1} style={{ width: "100%" }} />
            </Form.Item>
          </Col>

          <Col span={12}>
            <Form.Item name="related_purchase_id" label="Mã phiếu nhập">
              <InputNumber min={1} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
        </Row>

        {/* ===== NHÓM 3: NGƯỜI GIAO DỊCH ===== */}
        <Divider orientation="left">Người giao dịch</Divider>

        <Row gutter={16}>
          <Col span={12}>
            <Form.Item name="payer_receiver_name" label="Tên người giao dịch">
              <Input />
            </Form.Item>
          </Col>

          <Col span={12}>
            <Form.Item name="payer_receiver_phone" label="Số điện thoại">
              <Input />
            </Form.Item>
          </Col>

          <Col span={24}>
            <Form.Item name="payer_receiver_address" label="Địa chỉ">
              <Input.TextArea rows={2} />
            </Form.Item>
          </Col>

          <Col span={24}>
            <Form.Item name="note" label="Ghi chú">
              <Input.TextArea rows={2} />
            </Form.Item>
          </Col>
        </Row>
      </Form>
    </Modal>
  );
}
