import { useEffect, useMemo, useState } from "react";
import { Modal, Input, List, Button, Space, Tag, message } from "antd";
import apiClient from "../core/api";
import dayjs from "dayjs";

export default function PromotionSelectModal({ open, onClose, onSelect }) {
  const [loading, setLoading] = useState(false);
  const [promotions, setPromotions] = useState([]);
  const [search, setSearch] = useState("");

  useEffect(() => {
    if (!open) return;

    const fetchPromotions = async () => {
      setLoading(true);
      try {
        const res = await apiClient.get("/promotions", {
          params: { page: 1, limit: 500 },
        });

        // chỉ lấy khuyến mãi còn hiệu lực
        const today = dayjs();
        const valid = (res.data?.data || []).filter(
          (p) =>
            (!p.start_date || today.isAfter(dayjs(p.start_date).subtract(1, "day"))) &&
            (!p.end_date || today.isBefore(dayjs(p.end_date).add(1, "day")))
        );

        setPromotions(valid);
      } catch {
        message.error("Không tải được khuyến mãi");
      } finally {
        setLoading(false);
      }
    };

    setSearch("");
    fetchPromotions();
  }, [open]);

  const filtered = useMemo(() => {
    if (!search) return promotions;
    const q = search.toLowerCase();
    return promotions.filter((p) =>
      (p.name || "").toLowerCase().includes(q)
    );
  }, [promotions, search]);

  return (
    <Modal
      open={open}
      title="Chọn khuyến mãi"
      onCancel={onClose}
      footer={null}
      width={420}
      destroyOnClose
    >
      <Input
        placeholder="🔍 Tìm theo tên khuyến mãi"
        allowClear
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        style={{ marginBottom: 12 }}
        autoFocus
      />

      <List
        loading={loading}
        dataSource={filtered}
        rowKey="promotion_id"
        locale={{ emptyText: "Không có khuyến mãi phù hợp" }}
        renderItem={(p) => (
          <List.Item
            actions={[
              <Button
                type="primary"
                size="small"
                onClick={() => {
                  onSelect(p);
                  onClose();
                }}
              >
                Áp dụng
              </Button>,
            ]}
          >
            <Space direction="vertical" size={0}>
              <strong>{p.name}</strong>
              <Space size={8}>
                <Tag color="green">-{p.discount_percent}%</Tag>
                <span style={{ fontSize: 12, color: "#888" }}>
                  {p.end_date
                    ? `Hết hạn: ${dayjs(p.end_date).format("DD/MM/YYYY")}`
                    : "Không thời hạn"}
                </span>
              </Space>
            </Space>
          </List.Item>
        )}
      />
    </Modal>
  );
}
