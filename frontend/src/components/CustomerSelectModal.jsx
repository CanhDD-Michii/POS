import { useEffect, useMemo, useState } from "react";
import { Modal, Input, List, Button, Space, message } from "antd";
import apiClient from "../core/api";

export default function CustomerSelectModal({ open, onClose, onSelect }) {
  const [loading, setLoading] = useState(false);
  const [customers, setCustomers] = useState([]);
  const [search, setSearch] = useState("");

  useEffect(() => {
    if (!open) return;

    const fetchCustomers = async () => {
      setLoading(true);
      try {
        const res = await apiClient.get("/customers", {
          params: { page: 1, limit: 500 },
        });
        setCustomers(res.data?.data || []);
      } catch {
        message.error("Không tải được danh sách khách hàng");
      } finally {
        setLoading(false);
      }
    };

    setSearch("");
    fetchCustomers();
  }, [open]);

  const filtered = useMemo(() => {
    if (!search) return customers;
    const q = search.toLowerCase();
    return customers.filter(
      (c) =>
        (c.name || "").toLowerCase().includes(q) ||
        (c.phone || "").toLowerCase().includes(q)
    );
  }, [customers, search]);

  return (
    <Modal
      open={open}
      title="Chọn khách hàng"
      onCancel={onClose}
      footer={null}
      width={420}
      destroyOnClose
    >
      <Input
        placeholder="🔍 Tìm theo tên hoặc số điện thoại"
        allowClear
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        style={{ marginBottom: 12 }}
        autoFocus
      />

      <List
        loading={loading}
        dataSource={filtered}
        rowKey="customer_id"
        locale={{ emptyText: "Không tìm thấy khách hàng" }}
        renderItem={(c) => (
          <List.Item
            actions={[
              <Button
                type="primary"
                size="small"
                onClick={() => {
                  onSelect(c);
                  onClose();
                }}
              >
                Chọn
              </Button>,
            ]}
          >
            <Space direction="vertical" size={0}>
              <strong>{c.name || "Khách hàng mới"}</strong>
              <span style={{ fontSize: 12, color: "#888" }}>
                📞 {c.phone || "Không có SĐT"}
              </span>
            </Space>
          </List.Item>
        )}
      />
    </Modal>
  );
}
