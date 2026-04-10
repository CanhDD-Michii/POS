import { useEffect, useMemo, useState, useCallback } from "react";
import { Modal, Input, List, Avatar, Button, Space, message, Tag } from "antd";
import apiClient from "../core/api";

const BASE_URL = "http://localhost:3000";

export default function ProductSelectModalPurchase({ open, onClose, onSelect }) {
  const [loading, setLoading] = useState(false);
  const [allProducts, setAllProducts] = useState([]);
  const [search, setSearch] = useState("");

  const fetchAll = useCallback(async () => {
    setLoading(true);
    try {
      const out = [];
      let page = 1;
      const limit = 200;

      while (true) {
        const res = await apiClient.get("/products", { params: { page, limit } });
        const items = res.data?.data || [];
        const total = res.data?.pagination?.total ?? items.length;

        out.push(...items);
        if (out.length >= total || items.length === 0) break;
        page += 1;
      }

      // ❗ chỉ lấy sản phẩm còn kinh doanh
      setAllProducts(out.filter((p) => p.is_active !== false));
    } catch {
      message.error("Không tải được danh sách sản phẩm");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (open) {
      setSearch("");
      fetchAll();
    }
  }, [open, fetchAll]);

  const filtered = useMemo(() => {
    if (!search) return allProducts;
    const q = search.toLowerCase();
    return allProducts.filter(
      (p) =>
        (p.name || "").toLowerCase().includes(q) ||
        (p.barcode || "").toLowerCase().includes(q)
    );
  }, [allProducts, search]);

  const add = (p) => {
    onSelect({
      product_id: p.product_id,
      name: p.name,
      cost_price: p.cost_price ?? 0,
    });
  };

  return (
    <Modal
      title="📦 Chọn sản phẩm nhập kho"
      open={open}
      onCancel={onClose}
      footer={null}
      destroyOnClose
      width={600}
    >
      <Input
        placeholder="🔎 Tìm theo tên hoặc barcode..."
        allowClear
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        style={{ marginBottom: 12 }}
        autoFocus
      />

      <List
        loading={loading}
        dataSource={filtered}
        rowKey="product_id"
        locale={{ emptyText: "Không tìm thấy sản phẩm" }}
        renderItem={(item) => {
          const imgSrc = item.image_url
            ? item.image_url.startsWith("http")
              ? item.image_url
              : `${BASE_URL}${item.image_url}`
            : null;

          return (
            <List.Item
              actions={[
                <Button type="primary" onClick={() => add(item)}>
                  Chọn
                </Button>,
              ]}
            >
              <List.Item.Meta
                avatar={
                  imgSrc ? (
                    <Avatar shape="square" size={56} src={imgSrc} />
                  ) : (
                    <Avatar shape="square" size={56}>
                      {item.name?.[0] || "?"}
                    </Avatar>
                  )
                }
                title={
                  <Space direction="vertical" size={0}>
                    <span style={{ fontWeight: 600 }}>{item.name}</span>
                    <span style={{ fontSize: 12, color: "#888" }}>
                      Barcode: {item.barcode || "—"}
                    </span>
                  </Space>
                }
                description={
                  <Space size="large">
                    <span>
                      Giá nhập:{" "}
                      <b>
                        {Number(item.cost_price || 0).toLocaleString("vi-VN")}₫
                      </b>
                    </span>
                    <span>Tồn: {item.stock ?? "—"}</span>
                    {item.category_name && (
                      <Tag color="blue">{item.category_name}</Tag>
                    )}
                  </Space>
                }
              />
            </List.Item>
          );
        }}
      />
    </Modal>
  );
}
