import { useState, useEffect, useCallback, useMemo } from "react";
import {
  Table,
  Button,
  Input,
  DatePicker,
  Space,
  message,
  Popconfirm,
  Modal,
  Form,
  Drawer,
  Descriptions,
  Spin,
  InputNumber,
  Select,
  Divider,
} from "antd";
import { useRecoilValue } from "recoil";
import { userState } from "../core/atoms";
import apiClient from "../core/api";

const { RangePicker } = DatePicker;

export default function Categories() {
  const user = useRecoilValue(userState);
  const canManage = user?.role === "admin" || user?.role === "client";

  // ===== State =====
  const [allCategories, setAllCategories] = useState([]); // dữ liệu gốc từ backend
  const [filtered, setFiltered] = useState([]); // dữ liệu đã search/filter/sort
  const [pageData, setPageData] = useState([]); // dữ liệu hiển thị theo trang
  const [loading, setLoading] = useState(false);

  // filter + sort + paginate
  const [search, setSearch] = useState("");
  const [createdRange, setCreatedRange] = useState(null);
  const [sortOrder, setSortOrder] = useState("desc"); // 'asc' | 'desc'
  const [pagination, setPagination] = useState({ page: 1, pageSize: 10 });

  // modal category
  const [catModalOpen, setCatModalOpen] = useState(false);
  const [catModalMode, setCatModalMode] = useState("create"); // create | edit
  const [editingCategory, setEditingCategory] = useState(null);
  const [catForm] = Form.useForm();

  // detail drawer
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailData, setDetailData] = useState(null);

  // quick add product modal
  const [quickAddOpen, setQuickAddOpen] = useState(false);
  const [quickLoading, setQuickLoading] = useState(false);
  const [units, setUnits] = useState([]);
  const [suppliers, setSuppliers] = useState([]);
  const [quickForm] = Form.useForm();

  // ===== Fetch ALL categories once =====
  const fetchAll = useCallback(async () => {
    setLoading(true);
    try {
      const res = await apiClient.get("/categories");
      const rows = res.data?.data || [];
      setAllCategories(rows);
      setPagination((p) => ({ ...p, page: 1 }));
    } catch {
      message.error("Lỗi khi tải danh mục");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchAll();
  }, [fetchAll]);

  // ===== FE Search + Filter + Sort =====
  useEffect(() => {
    let data = [...allCategories];

    // search name
    if (search) {
      data = data.filter((c) =>
        c.name.toLowerCase().includes(search.toLowerCase())
      );
    }

    // filter date range
    if (createdRange?.length === 2) {
      const [start, end] = createdRange;
      const s = start.startOf("day").valueOf();
      const e = end.endOf("day").valueOf();
      data = data.filter((c) => {
        const t = new Date(c.created_at).getTime();
        return t >= s && t <= e;
      });
    }

    // sort by created_at
    data.sort((a, b) => {
      const tA = new Date(a.created_at).getTime();
      const tB = new Date(b.created_at).getTime();
      return sortOrder === "asc" ? tA - tB : tB - tA;
    });

    setFiltered(data);
    setPagination((p) => ({ ...p, page: 1 }));
  }, [allCategories, search, createdRange, sortOrder]);

  // ===== FE Pagination =====
  useEffect(() => {
    const start = (pagination.page - 1) * pagination.pageSize;
    const end = start + pagination.pageSize;
    setPageData(filtered.slice(start, end));
  }, [filtered, pagination]);

  // ===== CRUD Category =====
  const openCreate = () => {
    setCatModalMode("create");
    setEditingCategory(null);
    catForm.resetFields();
    setCatModalOpen(true);
  };

  const openEdit = (record) => {
    setCatModalMode("edit");
    setEditingCategory(record);
    catForm.setFieldsValue({
      name: record.name,
      description: record.description,
    });
    setCatModalOpen(true);
  };

  const submitCategory = async () => {
    const values = await catForm.validateFields();
    try {
      if (catModalMode === "create") {
        await apiClient.post("/categories", values);
        message.success("Đã tạo danh mục");
        fetchAll(); // ⬅️ gọi lại danh sách để cập nhật
      } else {
        await apiClient.put(
          `/categories/${editingCategory.category_id}`,
          values
        );
        message.success("Đã cập nhật danh mục");
      }
      setCatModalOpen(false);
      fetchAll();
    } catch {
      message.error("Lưu thất bại");
    }
  };

  const deleteCategory = async (id) => {
    try {
      await apiClient.delete(`/categories/${id}`);
      message.success("Đã xoá danh mục");
      fetchAll();
    } catch {
      message.error("Xoá thất bại");
    }
  };

  // ===== Detail Drawer =====
  const openDetail = async (record) => {
    setDetailOpen(true);
    setDetailLoading(true);
    try {
      const res = await apiClient.get(`/categories/${record.category_id}`);
      let data = res.data?.data || res.data;
      let products = data?.products || [];
      products = products.map((p) => ({
        product_id: p.product_id,
        name: p.name ?? p.product_name,
        barcode: p.barcode ?? "-",
        stock: p.stock ?? 0,
      }));
      data.products = products;
      setDetailData(data);
    } catch {
      message.error("Lỗi khi tải chi tiết");
    } finally {
      setDetailLoading(false);
    }
  };

  // ===== Quick Add Product =====
  const openQuickAdd = async () => {
    quickForm.resetFields();
    quickForm.setFieldsValue({ stock: 0, price: 0 });
    try {
      const [uRes, sRes] = await Promise.all([
        apiClient.get("/units"),
        apiClient.get("/suppliers"),
      ]);
      setUnits(uRes.data?.data || []);
      setSuppliers(sRes.data?.data || []);
    } catch {
      message.error("Lỗi khi tải đơn vị hoặc nhà cung cấp");
    }
    setQuickAddOpen(true);
  };

  const submitQuickAdd = async () => {
    const v = await quickForm.validateFields();
    try {
      setQuickLoading(true);
      await apiClient.post("/products", {
        name: v.name,
        barcode: v.barcode || null,
        stock: v.stock ?? 0,
        price: v.price ?? 0,
        category_id: detailData.category_id,
        unit_id: v.unit_id || null,
        supplier_id: v.supplier_id || null,
        image_url: v.image_url || null,
      });
      message.success("Đã thêm sản phẩm");
      setQuickAddOpen(false);
      openDetail(detailData);
    } catch {
      message.error("Thêm sản phẩm thất bại");
    } finally {
      setQuickLoading(false);
    }
  };

  // ===== Table columns =====
  const columns = useMemo(
    () => [
      {
        title: "Tên danh mục",
        dataIndex: "name",
        key: "name",
        render: (text, r) => (
          <Button type="link" onClick={() => openDetail(r)}>
            {text}
          </Button>
        ),
      },
      {
        title: "Ngày tạo",
        dataIndex: "created_at",
        key: "created_at",
        sorter: true,
        render: (val) => new Date(val).toLocaleDateString(),
      },
      {
        title: "Hành động",
        key: "action",
        render: (_, record) => (
          <Space>
            <Button onClick={() => openDetail(record)}>Chi tiết</Button>
            {canManage && (
              <>
                <Button onClick={() => openEdit(record)}>Sửa</Button>
                <Popconfirm
                  title="Xoá danh mục?"
                  onConfirm={() => deleteCategory(record.category_id)}
                >
                  <Button danger>Xoá</Button>
                </Popconfirm>
              </>
            )}
          </Space>
        ),
      },
    ],
    [canManage] // eslint-disable-line react-hooks/exhaustive-deps
  );

  // ===== Sort on table header click =====
  const onTableChange = (_, __, sorter) => {
    if (!sorter.order) return;
    setSortOrder(sorter.order === "ascend" ? "asc" : "desc");
  };

  return (
    <div style={{ padding: 16 }}>
      {/* HEADER */}
      <div
        style={{
          marginBottom: 16,
          padding: "12px 16px",
          background: "#ffffff",
          borderRadius: 8,
          border: "1px solid #e5e7eb",
        }}
      >
        <h2 style={{ margin: 0, color: "#2d3748" }}>🗂️ Quản lý Danh mục</h2>
        <p style={{ margin: "4px 0 0", color: "#718096", fontSize: 13 }}>
          Quản lý nhóm sản phẩm thuốc, dịch vụ và vật tư thú y
        </p>
      </div>

      {/* FILTERS */}
      <div
        style={{
          marginBottom: 16,
          padding: 12,
          background: "#ffffff",
          borderRadius: 8,
          border: "1px solid #e5e7eb",
        }}
      >
        <Space wrap>
          <Input
            placeholder="🔍 Tìm theo tên danh mục"
            value={search}
            allowClear
            onChange={(e) => setSearch(e.target.value)}
            style={{ width: 220 }}
          />
          <RangePicker value={createdRange} onChange={setCreatedRange} />
          {canManage && (
            <Button
              type="primary"
              onClick={openCreate}
              style={{ background: "#38a169", border: "none" }}
            >
              + Thêm danh mục
            </Button>
          )}
        </Space>
      </div>

      {/* TABLE */}
      <div
        style={{
          background: "#ffffff",
          borderRadius: 8,
          border: "1px solid #e5e7eb",
        }}
      >
        <Table
          rowKey="category_id"
          columns={columns}
          dataSource={pageData}
          loading={loading}
          pagination={{
            current: pagination.page,
            pageSize: pagination.pageSize,
            total: filtered.length,
            showSizeChanger: true,
            onChange: (page, pageSize) => setPagination({ page, pageSize }),
          }}
          onChange={onTableChange}
        />
      </div>

      {/* MODAL CREATE / EDIT */}
      <Modal
        title={
          catModalMode === "create" ? "🗂️ Thêm danh mục" : "✏️ Sửa danh mục"
        }
        open={catModalOpen}
        onCancel={() => setCatModalOpen(false)}
        onOk={submitCategory}
        okText="Lưu"
      >
        <Form layout="vertical" form={catForm}>
          <Form.Item
            name="name"
            label="Tên danh mục"
            rules={[{ required: true, message: "Nhập tên danh mục" }]}
          >
            <Input />
          </Form.Item>
          <Form.Item name="description" label="Mô tả">
            <Input.TextArea rows={3} />
          </Form.Item>
        </Form>
      </Modal>

      {/* DRAWER DETAIL */}
      <Drawer
        title="📂 Chi tiết danh mục"
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={700}
      >
        {detailLoading ? (
          <Spin />
        ) : detailData ? (
          <>
            <Descriptions bordered size="small" column={2}>
              <Descriptions.Item label="Tên danh mục">
                {detailData.name}
              </Descriptions.Item>
              <Descriptions.Item label="Ngày tạo">
                {new Date(detailData.created_at).toLocaleDateString()}
              </Descriptions.Item>
              <Descriptions.Item label="Mô tả" span={2}>
                {detailData.description || "-"}
              </Descriptions.Item>
            </Descriptions>

            <Divider />

            <Space style={{ marginBottom: 8 }}>
              <Button onClick={() => window.location.assign("/products")}>
                📦 Xem sản phẩm
              </Button>
              {canManage && (
                <Button
                  type="primary"
                  onClick={openQuickAdd}
                  style={{ background: "#38a169", border: "none" }}
                >
                  + Thêm sản phẩm
                </Button>
              )}
            </Space>

            <Table
              rowKey="product_id"
              columns={[
                { title: "Sản phẩm", dataIndex: "name" },
                { title: "Barcode", dataIndex: "barcode" },
                { title: "Tồn kho", dataIndex: "stock" },
              ]}
              dataSource={detailData.products}
              pagination={false}
              size="small"
            />
          </>
        ) : (
          <div>Không tìm thấy dữ liệu</div>
        )}
      </Drawer>

      {/* QUICK ADD PRODUCT */}
      <Modal
        title={
          detailData
            ? `➕ Thêm sản phẩm vào: ${detailData.name}`
            : "Thêm sản phẩm"
        }
        open={quickAddOpen}
        onCancel={() => setQuickAddOpen(false)}
        onOk={submitQuickAdd}
        okText="Lưu"
        confirmLoading={quickLoading}
      >
        <Form layout="vertical" form={quickForm}>
          <Form.Item
            label="Tên sản phẩm"
            name="name"
            rules={[{ required: true, message: "Nhập tên sản phẩm" }]}
          >
            <Input />
          </Form.Item>
          <Form.Item label="Barcode" name="barcode">
            <Input />
          </Form.Item>
          <Form.Item label="Tồn kho" name="stock">
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item label="Giá bán" name="price">
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item label="Đơn vị tính" name="unit_id">
            <Select
              allowClear
              placeholder="Chọn đơn vị"
              options={units.map((u) => ({
                value: u.unit_id,
                label: u.name,
              }))}
            />
          </Form.Item>
          <Form.Item label="Nhà cung cấp" name="supplier_id">
            <Select
              allowClear
              placeholder="Chọn nhà cung cấp"
              options={suppliers.map((s) => ({
                value: s.supplier_id,
                label: s.name,
              }))}
            />
          </Form.Item>
          <Form.Item name="image_url" label="Ảnh (URL)">
            <Input placeholder="https://..." />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
