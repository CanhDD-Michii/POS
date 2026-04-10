import { Modal, Select } from "antd";
import { useEffect, useState } from "react";
import apiClient from "../core/api";

function PaymentModal({ visible, onOk, onCancel }) {
  const [methods, setMethods] = useState([]);
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    if (visible) {
      apiClient.get("/payment-methods").then((res) => setMethods(res.data.data || []));
    }
  }, [visible]);

  return (
    <Modal
      title="Chọn phương thức thanh toán"
      open={visible}
      onOk={() => onOk(selected)}
      onCancel={onCancel}
      okButtonProps={{ disabled: !selected }}
    >
      <Select
        placeholder="Chọn phương thức"
        value={selected}
        onChange={setSelected}
        style={{ width: "100%" }}
      >
        {methods.map((m) => (
          <Select.Option key={m.payment_method_id} value={m.payment_method_id}>
            {m.name}
          </Select.Option>
        ))}
      </Select>
    </Modal>
  );
}

export default PaymentModal;
