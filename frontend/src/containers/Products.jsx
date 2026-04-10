import { useEffect, useState } from "react";
import {
  Table,
  Input,
  Space,
  Button,
  Drawer,
  Descriptions,
  Image,
  Popconfirm,
  message,
  InputNumber,
  Select,
} from "antd";
import { useRecoilValue } from "recoil";
import { userState } from "../core/atoms";
import apiClient from "../core/api";
import ProductForm from "../components/ProductForm";

const BASE_URL = "http://localhost:3000";

export default function Products() {
  const user = useRecoilValue(userState);
  const role = user?.role;
  const isAdmin = role === "admin";
  const canEdit = isAdmin || role === "client";

  const [products, setProducts] = useState([]);
  const [categories, setCategories] = useState([]);
  const [suppliers, setSuppliers] = useState([]);

  const [search, setSearch] = useState("");
  const [categoryId, setCategoryId] = useState(null);
  const [supplierId, setSupplierId] = useState(null);
  const [stockMin, setStockMin] = useState();
  const [stockMax, setStockMax] = useState();

  const [loading, setLoading] = useState(false);
  const [detailOpen, setDetailOpen] = useState(false);
  const [detail, setDetail] = useState(null);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState(null);

  // Load danh sách
  const fetchProducts = async () => {
    setLoading(true);
    try {
      const res = await apiClient.get("/products");
      setProducts(res.data?.data || []);
    } catch {
      message.error("Lỗi tải sản phẩm");
    }
    setLoading(false);
  };

  // Load categories & suppliers
  const fetchFilters = async () => {
    try {
      const resC = await apiClient.get("/categories");
      const resS = await apiClient.get("/suppliers");
      setCategories(resC.data?.data || []);
      setSuppliers(resS.data?.data || []);
    } catch {
      message.error("Lỗi tải filters");
    }
  };

  useEffect(() => {
    fetchProducts();
    fetchFilters();
  }, []);

  // Filter tổng hợp
  const filteredProducts = products.filter((p) => {
    const q = search.toLowerCase();
    if (
      search &&
      !(
        p.name?.toLowerCase().includes(q) ||
        p.barcode?.toLowerCase().includes(q)
      )
    ) {
      return false;
    }
    if (categoryId && p.category_id !== categoryId) {
      return false;
    }
    if (supplierId && p.supplier_id !== supplierId) {
      return false;
    }
    if (typeof stockMin === "number" && (p.stock ?? 0) < stockMin) {
      return false;
    }
    if (typeof stockMax === "number" && (p.stock ?? 0) > stockMax) {
      return false;
    }
    return true;
  });

  // Drawer chi tiết
  const openDetail = async (row) => {
    try {
      const res = await apiClient.get(`/products/${row.product_id}`);
      setDetail(res.data?.data || null);
      setDetailOpen(true);
    } catch {
      message.error("Lỗi tải chi tiết");
    }
  };

  // Mở form create
  const openCreate = () => {
    setEditing(null);
    setFormOpen(true);
  };

  // Mở form edit
  const openEdit = async (row) => {
    try {
      const res = await apiClient.get(`/products/${row.product_id}`);
      setEditing(res.data?.data || null);
      setFormOpen(true);
    } catch {
      message.error("Lỗi tải dữ liệu sản phẩm");
    }
  };

  // Xóa sản phẩm
  const disableProduct = async (id) => {
    if (!isAdmin) return;
    try {
      await apiClient.put(`/products/${id}/disable`);
      message.success("Đã ngừng kinh doanh sản phẩm");
      fetchProducts();
    } catch {
      message.error("Thao tác thất bại");
    }
  };

  // Cột bảng
  const columns = [
    {
      title: "Ảnh",
      dataIndex: "image_url",
      width: 70,
      render: (url) =>
        url ? (
          <Image
            src={`${BASE_URL}${url}`}
            width={100}
            height={100}
            style={{ objectFit: "cover", borderRadius: 6 }}
            preview
          />
        ) : (
          <div style={{ width: 50, height: 50, background: "#f1f1f1" }} />
        ),
    },
    { title: "Tên", dataIndex: "name" },
    { title: "Barcode", dataIndex: "barcode" },
    { title: "Tồn kho", dataIndex: "stock" },
    {
      title: "Giá bán",
      dataIndex: "price",
      render: (price) => {
        // Chuyển đổi giá thành định dạng dễ đọc
        return price ? `${Number(price).toLocaleString("vi-VN")} đ` : "—"; // Hiển thị "—" nếu không có giá
      },
    },
    {
      title: "Hành động",
      render: (_, row) => (
        <Space>
          <Button onClick={() => openDetail(row)}>Chi tiết</Button>
          {canEdit && <Button onClick={() => openEdit(row)}>Sửa</Button>}
          {isAdmin && (
            <Popconfirm
              title="Xóa sản phẩm này?"
              onConfirm={() => disableProduct(row.product_id)}
            >
              <Button>Ngừng kinh doanh</Button>
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ];

  return (
    <div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 12,
          marginBottom: 20,
          padding: "6px 0",
        }}
      >
        <div
          style={{
            background: "#1890ff20",
            padding: 12,
            borderRadius: 12,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <span style={{ fontSize: 28 }}>📦</span>
        </div>

        <div>
          <h1
            style={{
              margin: 0,
              fontSize: "1.8rem",
              fontWeight: 800,
              letterSpacing: "0.3px",
              color: "#0f1c2e",
            }}
          >
            Quản lý Sản phẩm
          </h1>

          <div style={{ fontSize: 14, opacity: 0.6 }}>
            Tra cứu – Quản lý – Thêm mới – Chỉnh sửa sản phẩm
          </div>
        </div>
      </div>

      {/* Search & Filter UI */}
      <div
        style={{
          display: "flex",
          flexWrap: "wrap",
          gap: 12,
          marginBottom: 16,
          alignItems: "center",
        }}
      >
        <Input
          placeholder="🔎 Tìm theo tên hoặc barcode"
          allowClear
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ width: 230 }}
        />

        <Select
          allowClear
          placeholder="📂 Danh mục"
          value={categoryId}
          onChange={setCategoryId}
          style={{ width: 200 }}
          options={categories.map((c) => ({
            value: c.category_id,
            label: c.name,
          }))}
        />

        <Select
          allowClear
          placeholder="🏭 Nhà cung cấp"
          value={supplierId}
          onChange={setSupplierId}
          style={{ width: 200 }}
          options={suppliers.map((s) => ({
            value: s.supplier_id,
            label: s.name,
          }))}
        />

        <InputNumber
          placeholder="Tồn tối thiểu"
          min={0}
          value={stockMin}
          onChange={setStockMin}
          style={{ width: 150 }}
        />

        <InputNumber
          placeholder="Tồn tối đa"
          min={0}
          value={stockMax}
          onChange={setStockMax}
          style={{ width: 150 }}
        />

        {canEdit && (
          <Button
            type="primary"
            onClick={openCreate}
            style={{
              fontWeight: 600,
              padding: "0 16px",
            }}
          >
            ➕ Thêm sản phẩm
          </Button>
        )}
      </div>

      <Table
        rowKey="product_id"
        loading={loading}
        columns={columns}
        dataSource={filteredProducts}
      />

      {/* Drawer Chi tiết */}
      <Drawer
        title="Chi tiết sản phẩm"
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={720}
      >
        {detail ? (
          <>
            {detail.image_url && (
              <div style={{ marginBottom: 12 }}>
                <Image
                  src={`${BASE_URL}${detail.image_url}`}
                  width={200}
                  style={{ borderRadius: 8 }}
                />
              </div>
            )}
            <Descriptions bordered size="small" column={2}>
              <Descriptions.Item label="Tên">{detail.name}</Descriptions.Item>
              <Descriptions.Item label="Barcode">
                {detail.barcode}
              </Descriptions.Item>
              <Descriptions.Item label="Giá bán">
                {detail.price
                  ? `${Number(detail.price).toLocaleString("vi-VN")} đ`
                  : "—"}
              </Descriptions.Item>
              <Descriptions.Item label="Giá vốn">
                {detail.cost_price
                  ? `${Number(detail.cost_price).toLocaleString("vi-VN")} đ`
                  : "—"}
              </Descriptions.Item>
              <Descriptions.Item label="Tồn kho">
                {detail.stock}
              </Descriptions.Item>
              <Descriptions.Item label="Tồn tối thiểu">
                {detail.minimum_inventory}
              </Descriptions.Item>
              <Descriptions.Item label="Tồn tối đa">
                {detail.maximum_inventory}
              </Descriptions.Item>
              <Descriptions.Item label="Danh mục">
                {detail.category_name}
              </Descriptions.Item>
              <Descriptions.Item label="Nhà cung cấp">
                {detail.supplier_name}
              </Descriptions.Item>
              <Descriptions.Item label="Mô tả" span={2}>
                {detail.description}
              </Descriptions.Item>
            </Descriptions>
          </>
        ) : (
          "Không tìm thấy"
        )}
      </Drawer>

      {/* Form Create/Edit */}
      <ProductForm
        open={formOpen}
        onClose={() => setFormOpen(false)}
        onSuccess={() => {
          setFormOpen(false);
          fetchProducts();
        }}
        editing={editing}
      />
    </div>
  );
}
