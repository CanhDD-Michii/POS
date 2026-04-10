import { useState, useEffect, useCallback, useMemo } from "react";
import {
  Table,
  Button,
  Input,
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

export default function Units() {
  const user = useRecoilValue(userState);
  const canManage = user?.role === "admin" || user?.role === "client";

  // ===== State (List) =====
  const [allUnits, setAllUnits] = useState([]);
  const [filtered, setFiltered] = useState([]);
  const [pageData, setPageData] = useState([]);
  const [search, setSearch] = useState("");
  const [sortOrder, setSortOrder] = useState("desc"); // asc/desc
  const [loading, setLoading] = useState(false);
  const [pagination, setPagination] = useState({ page: 1, pageSize: 10 });

  // ===== State (Create/Edit Modal) =====
  const [unitModalOpen, setUnitModalOpen] = useState(false);
  const [unitModalMode, setUnitModalMode] = useState("create");
  const [editingUnit, setEditingUnit] = useState(null);
  const [unitForm] = Form.useForm();

  // ===== State (Detail Drawer) =====
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailData, setDetailData] = useState(null);

  // ===== State (Quick Add Product Modal) =====
  const [quickAddOpen, setQuickAddOpen] = useState(false);
  const [quickLoading, setQuickLoading] = useState(false);
  const [unitsDropdown, setUnitsDropdown] = useState([]); // eslint-disable-line no-unused-vars
  const [suppliersDropdown, setSuppliersDropdown] = useState([]);
  const [quickForm] = Form.useForm();

  // ===== Fetch ALL units =====
  const fetchAll = useCallback(async () => {
    setLoading(true);
    try {
      const res = await apiClient.get("/units");
      const rows = res.data?.data || [];
      setAllUnits(rows);
      setPagination((p) => ({ ...p, page: 1 }));
    } catch {
      message.error("Lỗi khi tải đơn vị đo");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchAll();
  }, [fetchAll]);

  // ===== FE Search + Sort =====
  useEffect(() => {
    let data = [...allUnits];

    if (search) {
      data = data.filter((u) =>
        u.name.toLowerCase().includes(search.toLowerCase())
      );
    }

    data.sort((a, b) => {
      const A = a.unit_id;
      const B = b.unit_id;
      return sortOrder === "asc" ? A - B : B - A;
    });

    setFiltered(data);
    setPagination((p) => ({ ...p, page: 1 }));
  }, [allUnits, search, sortOrder]);

  // ===== FE Pagination =====
  useEffect(() => {
    const start = (pagination.page - 1) * pagination.pageSize;
    const end = start + pagination.pageSize;
    setPageData(filtered.slice(start, end));
  }, [filtered, pagination]);

  // ===== CRUD =====
  const openCreate = () => {
    setUnitModalMode("create");
    setEditingUnit(null);
    unitForm.resetFields();
    setUnitModalOpen(true);
  };

  const openEdit = (record) => {
    setUnitModalMode("edit");
    setEditingUnit(record);
    unitForm.setFieldsValue({
      name: record.name,
      description: record.description,
    });
    setUnitModalOpen(true);
  };

  const submitUnit = async () => {
    const v = await unitForm.validateFields();
    try {
      if (unitModalMode === "create") {
        await apiClient.post("/units", v);
      } else {
        await apiClient.put(`/units/${editingUnit.unit_id}`, v);
      }
      setUnitModalOpen(false);
      fetchAll();
    } catch {
      message.error("Lưu thất bại");
    }
  };

  const deleteUnit = async (id) => {
    try {
      await apiClient.delete(`/units/${id}`);
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
      const res = await apiClient.get(`/units/${record.unit_id}`);
      let data = res.data?.data || res.data;
      let products = data?.products || [];
      products = products
        .filter((p) => p.product_id)
        .map((p) => ({
          product_id: p.product_id,
          name: p.name ?? p.product_name,
          price: p.price ?? 0,
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
    quickForm.setFieldsValue({ price: 0 });
    try {
      const [uRes, sRes] = await Promise.all([
        apiClient.get("/units"),
        apiClient.get("/suppliers"),
      ]);
      setUnitsDropdown(uRes.data?.data || []);
      setSuppliersDropdown(sRes.data?.data || []);
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
        unit_id: detailData.unit_id,
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

  // ===== Table Columns =====
  const columns = useMemo(
    () => [
      {
        title: "Tên đơn vị",
        dataIndex: "name",
        key: "name",
        render: (text, r) => (
          <Button type="link" onClick={() => openDetail(r)}>
            {text}
          </Button>
        ),
      },
      { title: "Mô tả", dataIndex: "description", key: "description" },
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
                  title="Xoá đơn vị này?"
                  onConfirm={() => deleteUnit(record.unit_id)}
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

  return (
    <div>
      <h2>Quản lý Đơn vị đo</h2>

      {/* Filters */}
      <Space style={{ marginBottom: 12 }}>
        <Input
          placeholder="Tìm theo tên"
          value={search}
          allowClear
          onChange={(e) => setSearch(e.target.value)}
          style={{ width: 200 }}
        />
        {canManage && (
          <Button type="primary" onClick={openCreate}>
            Thêm đơn vị
          </Button>
        )}
      </Space>

      {/* Table */}
      <Table
        rowKey="unit_id"
        columns={columns}
        dataSource={pageData}
        loading={loading}
        pagination={{
          current: pagination.page,
          pageSize: pagination.pageSize,
          total: filtered.length,
          showSizeChanger: true,
          onChange: (page, pageSize) =>
            setPagination({ page, pageSize }),
        }}
        onChange={(_, __, sorter) => {
          if (!sorter.order) return;
          setSortOrder(sorter.order === "ascend" ? "asc" : "desc");
        }}
      />

      {/* Modal Create/Edit */}
      <Modal
        title={unitModalMode === "create" ? "Thêm đơn vị" : "Sửa đơn vị"}
        open={unitModalOpen}
        onCancel={() => setUnitModalOpen(false)}
        onOk={submitUnit}
        okText="Lưu"
      >
        <Form layout="vertical" form={unitForm}>
          <Form.Item
            name="name"
            label="Tên đơn vị"
            rules={[{ required: true, message: "Nhập tên đơn vị" }]}
          >
            <Input />
          </Form.Item>
          <Form.Item name="description" label="Mô tả">
            <Input.TextArea />
          </Form.Item>
        </Form>
      </Modal>

      {/* Drawer Detail */}
      <Drawer
        title="Chi tiết đơn vị đo"
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={680}
      >
        {detailLoading ? (
          <Spin />
        ) : detailData ? (
          <>
            <Descriptions bordered size="small" column={2}>
              <Descriptions.Item label="Tên">
                {detailData.name}
              </Descriptions.Item>
              <Descriptions.Item label="Mô tả">
                {detailData.description || "-"}
              </Descriptions.Item>
            </Descriptions>

            <Divider />

            <Space style={{ marginBottom: 8 }}>
              <Button onClick={() => window.location.assign("/products")}>
                Đi tới trang Sản phẩm
              </Button>
              {canManage && (
                <Button type="primary" onClick={openQuickAdd}>
                  Thêm sản phẩm vào đơn vị
                </Button>
              )}
            </Space>

            <Table
              rowKey="product_id"
              columns={[
                { title: "Sản phẩm", dataIndex: "name" },
                { title: "Giá", dataIndex: "price" },
              ]}
              dataSource={detailData.products}
              pagination={false}
            />
          </>
        ) : (
          <div>Không tìm thấy dữ liệu</div>
        )}
      </Drawer>

      {/* Modal Quick Add Product */}
      <Modal
        title={
          detailData
            ? `Thêm sản phẩm vào: ${detailData.name}`
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
          <Form.Item label="Nhà cung cấp" name="supplier_id">
            <Select
              allowClear
              placeholder="Chọn nhà cung cấp"
              options={suppliersDropdown.map((s) => ({
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
