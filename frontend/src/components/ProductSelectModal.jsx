import { useEffect, useMemo, useState, useCallback } from "react";
import { Modal, Input, List, Avatar, Button, Space, message } from "antd";
import apiClient from "../core/api";

export default function ProductSelectModal({ visible, onClose, onSelect }) {
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
      setAllProducts(out);
    } catch {
      message.error("Không tải được danh sách sản phẩm");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (visible) {
      setSearch("");
      fetchAll();
    }
  }, [visible, fetchAll]);

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
    if (p.stock !== undefined && p.stock <= 0) {
      message.warning("Sản phẩm đã hết hàng");
      return;
    }
    // chuẩn hoá object đưa vào cart
    onSelect({
      product_id: p.product_id,
      name: p.name,
      price: p.price,
      stock: p.stock ?? Infinity,
      image_url: p.image_url,
      barcode: p.barcode,
    });
  };

  return (
    <Modal
      title="Chọn sản phẩm"
      open={visible}
      onCancel={onClose}
      footer={null}
      destroyOnClose
      width={560}
    >
      <Input
        placeholder="Tìm theo tên / barcode..."
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
        renderItem={(item) => (
          <List.Item
            actions={[
              <Button type="primary" onClick={() => add(item)}>
                Chọn
              </Button>,
            ]}
          >
            <List.Item.Meta
              avatar={(() => {
                const imgSrc = item.image_url
                  ? (item.image_url.startsWith('http') ? item.image_url : `http://localhost:3000${item.image_url}`)
                  : undefined;
                return imgSrc ? (
                  <Avatar shape="square" size={48} src={imgSrc} />
                ) : (
                  <Avatar shape="square" size={48}>
                    {item.name?.[0] || "?"}
                  </Avatar>
                );
              })()}
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
                  <span>Giá: {Number(item.price).toLocaleString()} đ</span>
                  <span>Tồn: {item.stock ?? "—"}</span>
                  <span>Danh mục: {item.category_name || "—"}</span>
                </Space>
              }
            />
          </List.Item>
        )}
      />
    </Modal>
  );
}
