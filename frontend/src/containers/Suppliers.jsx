import { useState, useEffect, useCallback, useMemo } from "react";
import {
  Table,
  Input,
  Space,
  Button,
  Modal,
  Form,
  message,
  Drawer,
  Descriptions,
  Popconfirm,
  InputNumber,
  Select,
  Upload,
} from "antd";
import { UploadOutlined } from "@ant-design/icons";
import { useRecoilValue } from "recoil";
import { userState } from "../core/atoms";
import apiClient from "../core/api";

export default function Suppliers() {
  const user = useRecoilValue(userState);
  const role = user?.role;
  const isAdmin = role === "admin";

  // ===== List state =====
  const [allSuppliers, setAllSuppliers] = useState([]); // raw từ /suppliers
  const [search, setSearch] = useState(""); // name/phone
  const [sorter, setSorter] = useState({ field: null, order: null }); // name/phone
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [loading, setLoading] = useState(false);

  // ===== Create/Edit modal =====
  const [supModalOpen, setSupModalOpen] = useState(false);
  const [supModalMode, setSupModalMode] = useState("create"); // create | edit
  const [editing, setEditing] = useState(null);
  const [supForm] = Form.useForm();

  // ===== Detail Drawer =====
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detail, setDetail] = useState(null); // từ GET /suppliers/:id

  // ===== Quick Add Product (FULL FORM) =====
  const [quickOpen, setQuickOpen] = useState(false);
  const [quickLoading, setQuickLoading] = useState(false);
  const [quickForm] = Form.useForm();
  const [fileList, setFileList] = useState([]);
  const [categories, setCategories] = useState([]); // cho chọn category
  const [units, setUnits] = useState([]); // cho chọn unit

  // ---------- Fetch suppliers (ALL, FE paginate) ----------
  const fetchAllSuppliers = useCallback(async () => {
    setLoading(true);
    try {
      const out = [];
      let p = 1;
      const limit = 200;
      while (true) {
        const res = await apiClient.get("/suppliers", { params: { page: p, limit } });
        const items = res.data?.data || [];
        const total = res.data?.pagination?.total ?? items.length;
        out.push(...items);
        if (out.length >= total || items.length === 0) break;
        p += 1;
      }
      setAllSuppliers(out);
      setPage(1);
    } catch {
      message.error("Lỗi tải danh sách nhà cung cấp");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchAllSuppliers();
  }, [fetchAllSuppliers]);

  // ---------- FE filter/sort ----------
  const filtered = useMemo(() => {
    let rows = [...allSuppliers];

    if (search) {
      const q = search.toLowerCase();
      rows = rows.filter(
        (r) =>
          (r.name || "").toLowerCase().includes(q) ||
          (r.phone || "").toLowerCase().includes(q)
      );
    }

    if (sorter.field && sorter.order) {
      const dir = sorter.order === "ascend" ? 1 : -1;
      const field = sorter.field;
      rows.sort((a, b) => {
        const A = a[field] ?? "";
        const B = b[field] ?? "";
        return A.toString().localeCompare(B.toString()) * dir;
      });
    }

    return rows;
  }, [allSuppliers, search, sorter]);

  const pageData = useMemo(() => {
    const start = (page - 1) * pageSize;
    return filtered.slice(start, start + pageSize);
  }, [filtered, page, pageSize]);

  // ---------- CRUD Supplier ----------
  const openCreate = () => {
    if (!isAdmin) return;
    setSupModalMode("create");
    setEditing(null);
    supForm.resetFields();
    setSupModalOpen(true);
  };

  const openEdit = (row) => {
    if (!isAdmin) return;
    setSupModalMode("edit");
    setEditing(row);
    supForm.setFieldsValue({
      name: row.name,
      phone: row.phone,
      email: row.email,
      address: row.address,
    });
    setSupModalOpen(true);
  };

  const submitSupplier = async () => {
    const v = await supForm.validateFields();
    try {
      if (supModalMode === "create") {
        await apiClient.post("/suppliers", v);
        message.success("Đã tạo nhà cung cấp");
      } else {
        await apiClient.put(`/suppliers/${editing.supplier_id}`, v);
        message.success("Đã cập nhật nhà cung cấp");
      }
      setSupModalOpen(false);
      fetchAllSuppliers();
    } catch {
      message.error("Lưu thất bại");
    }
  };

  const deleteSupplier = async (row) => {
    if (!isAdmin) return;
    try {
      await apiClient.delete(`/suppliers/${row.supplier_id}`);
      message.success("Đã xoá nhà cung cấp");
      fetchAllSuppliers();
      if (detail?.supplier_id === row.supplier_id) setDetailOpen(false);
    } catch {
      message.error("Xoá thất bại");
    }
  };

  // ---------- Detail Drawer ----------
  const openDetail = async (row) => {
    setDetailOpen(true);
    setDetailLoading(true);
    try {
      const res = await apiClient.get(`/suppliers/${row.supplier_id}`);
      // API trả: s.* + products: [{ product_name, stock }]
      const data = res.data?.data || res.data;
      const products = (data.products || [])
        .filter((p) => p?.product_name)
        .map((p, idx) => ({ key: idx, product_name: p.product_name, stock: p.stock ?? 0 }));
      data.products = products;
      setDetail(data);
    } catch {
      message.error("Lỗi tải chi tiết nhà cung cấp");
    } finally {
      setDetailLoading(false);
    }
  };

  // ---------- Quick Add Product (FULL FORM) ----------
  const openQuickAdd = async () => {
    if (!isAdmin) return;
    quickForm.resetFields();
    setFileList([]);
    // load dropdowns
    try {
      const [cRes, uRes] = await Promise.all([
        apiClient.get("/categories", { params: { page: 1, limit: 500 } }),
        apiClient.get("/units", { params: { page: 1, limit: 500 } }),
      ]);
      setCategories(cRes.data?.data || []);
      setUnits(uRes.data?.data || []);
    } catch {
        message.error("Lỗi khi tải danh mục hoặc đơn vị");
    }
    setQuickOpen(true);
  };

  const submitQuickAdd = async () => {
    const v = await quickForm.validateFields();
    const fd = new FormData();
    // bám API products POST
    const fields = [
      "name",
      "barcode",
      "price",
      "cost_price",
      "stock",
      "minimum_inventory",
      "category_id",
      "unit_id",
      "supplier_id",
    ];
    // supplier_id auto-fill theo supplier đang xem
    const values = { ...v, supplier_id: detail?.supplier_id };
    for (const k of fields) {
      const val = values[k];
      if (val !== undefined && val !== null && val !== "") fd.append(k, val);
    }
    if (fileList.length > 0) {
      fd.append("image", fileList[0].originFileObj);
    }

    try {
      setQuickLoading(true);
      await apiClient.post("/products", fd, {
        headers: { "Content-Type": "multipart/form-data" },
      });
      message.success("Đã thêm sản phẩm cho nhà cung cấp");
      setQuickOpen(false);
      // refresh detail để thấy sp mới
      if (detail?.supplier_id) {
        const res = await apiClient.get(`/suppliers/${detail.supplier_id}`);
        const data = res.data?.data || res.data;
        const products = (data.products || [])
          .filter((p) => p?.product_name)
          .map((p, idx) => ({ key: idx, product_name: p.product_name, stock: p.stock ?? 0 }));
        data.products = products;
        setDetail(data);
      }
    } catch {
      message.error("Thêm sản phẩm thất bại");
    } finally {
      setQuickLoading(false);
    }
  };

  // ---------- Columns ----------
  const columns = useMemo(
    () => [
      {
        title: "Tên",
        dataIndex: "name",
        key: "name",
        sorter: true,
        render: (text, r) => (
          <Button type="link" onClick={() => openDetail(r)}>
            {text}
          </Button>
        ),
      },
      { title: "Điện thoại", dataIndex: "phone", key: "phone", sorter: true },
      { title: "Email", dataIndex: "email", key: "email" },
      {
        title: "Hành động",
        key: "action",
        render: (_, row) => (
          <Space>
            <Button onClick={() => openDetail(row)}>Chi tiết</Button>
            {isAdmin && (
              <>
                <Button onClick={() => openEdit(row)}>Sửa</Button>
                <Popconfirm title="Xoá nhà cung cấp này?" onConfirm={() => deleteSupplier(row)}>
                  <Button danger>Xoá</Button>
                </Popconfirm>
              </>
            )}
          </Space>
        ),
      },
    ],
    [isAdmin] // eslint-disable-line react-hooks/exhaustive-deps
  );

  // ---------- Render ----------
  return (
    <div>
      <h2>Quản lý Nhà cung cấp</h2>

      {/* Filters */}
      <Space style={{ marginBottom: 12 }} wrap>
        <Input
          placeholder="Tìm theo tên / điện thoại"
          allowClear
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ width: 260 }}
        />
        {isAdmin && (
          <Button type="primary" onClick={openCreate}>
            Thêm nhà cung cấp
          </Button>
        )}
      </Space>

      {/* Table */}
      <Table
        rowKey="supplier_id"
        loading={loading}
        columns={columns}
        dataSource={pageData}
        pagination={{
          current: page,
          pageSize,
          total: filtered.length,
          showSizeChanger: true,
          onChange: (p, ps) => {
            setPage(p);
            setPageSize(ps);
          },
        }}
        onChange={(_, __, s) => {
          if (!s?.field) return;
          setSorter({ field: s.field, order: s.order });
        }}
      />

      {/* Modal Create/Edit Supplier */}
      <Modal
        title={supModalMode === "create" ? "Thêm nhà cung cấp" : "Sửa nhà cung cấp"}
        open={supModalOpen}
        onCancel={() => setSupModalOpen(false)}
        onOk={submitSupplier}
        okText="Lưu"
      >
        <Form layout="vertical" form={supForm}>
          <Form.Item name="name" label="Tên" rules={[{ required: true, message: "Nhập tên" }]}>
            <Input />
          </Form.Item>
          <Form.Item name="phone" label="Điện thoại">
            <Input />
          </Form.Item>
          <Form.Item name="email" label="Email">
            <Input />
          </Form.Item>
          <Form.Item name="address" label="Địa chỉ">
            <Input />
          </Form.Item>
        </Form>
      </Modal>

      {/* Drawer Detail Supplier */}
      <Drawer
        title="Chi tiết nhà cung cấp"
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={720}
      >
        {detailLoading ? (
          "Đang tải..."
        ) : detail ? (
          <>
            <Descriptions bordered size="small" column={2}>
              <Descriptions.Item label="Tên">{detail.name}</Descriptions.Item>
              <Descriptions.Item label="Điện thoại">{detail.phone || "-"}</Descriptions.Item>
              <Descriptions.Item label="Email">{detail.email || "-"}</Descriptions.Item>
              <Descriptions.Item label="Địa chỉ" span={2}>
                {detail.address || "-"}
              </Descriptions.Item>
            </Descriptions>

            <div style={{ marginTop: 12, marginBottom: 8, fontWeight: 600 }}>
              Sản phẩm do nhà cung cấp này cung cấp
            </div>
            <Table
              rowKey="key"
              columns={[
                { title: "Sản phẩm", dataIndex: "product_name" },
                { title: "Tồn kho", dataIndex: "stock" },
              ]}
              dataSource={detail.products || []}
              pagination={false}
              size="small"
            />

            {isAdmin && (
              <>
                <div style={{ marginTop: 16, fontWeight: 600 }}>Thêm sản phẩm nhanh</div>
                <Button type="primary" style={{ marginBottom: 8 }} onClick={openQuickAdd}>
                  Thêm sản phẩm cho nhà cung cấp
                </Button>
              </>
            )}
          </>
        ) : (
          <div>Không tìm thấy</div>
        )}
      </Drawer>

      {/* Modal Quick Add Product (FULL FORM) */}
      <Modal
        title={
          detail
            ? `Thêm sản phẩm cho: ${detail.name}`
            : "Thêm sản phẩm"
        }
        open={quickOpen}
        onCancel={() => setQuickOpen(false)}
        onOk={submitQuickAdd}
        okText="Lưu"
        confirmLoading={quickLoading}
      >
        <Form layout="vertical" form={quickForm}>
          <Form.Item name="name" label="Tên sản phẩm" rules={[{ required: true, message: "Nhập tên sản phẩm" }]}>
            <Input />
          </Form.Item>
          <Form.Item name="barcode" label="Barcode">
            <Input />
          </Form.Item>
          <Form.Item name="price" label="Giá bán">
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item name="cost_price" label="Giá vốn">
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item name="stock" label="Tồn kho">
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item name="minimum_inventory" label="Tồn tối thiểu">
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item name="category_id" label="Danh mục">
            <Select
              allowClear
              placeholder="Chọn danh mục"
              options={categories.map((c) => ({ value: c.category_id, label: c.name }))}
            />
          </Form.Item>
          <Form.Item name="unit_id" label="Đơn vị tính">
            <Select
              allowClear
              placeholder="Chọn đơn vị"
              options={units.map((u) => ({ value: u.unit_id, label: u.name }))}
            />
          </Form.Item>
          <Form.Item label="Ảnh (upload)">
            <Upload
              beforeUpload={() => false}
              fileList={fileList}
              onChange={({ fileList: fl }) => setFileList(fl.slice(-1))}
              maxCount={1}
            >
              <Button icon={<UploadOutlined />}>Chọn ảnh</Button>
            </Upload>
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}
