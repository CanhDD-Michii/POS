import { useEffect, useState, useMemo, useCallback } from "react";
import {
  Table,
  Input,
  Space,
  Button,
  Modal,
  Form,
  InputNumber,
  DatePicker,
  message,
  Drawer,
  Descriptions,
  Popconfirm,
  Select,
} from "antd";
import { useRecoilValue } from "recoil";
import { userState } from "../core/atoms";
import apiClient from "../core/api";
import { useNavigate } from "react-router-dom";
import dayjs from "dayjs";

export default function Promotions() {
  const user = useRecoilValue(userState);
  const role = user?.role;
  const isAdmin = role === "admin";
  const canView = role === "admin" || role === "client";
  const navigate = useNavigate();

  // List State
  const [allPromotions, setAllPromotions] = useState([]);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState("");
  const [sorter, setSorter] = useState({ field: null, order: null });
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);

  // Modal Create/Edit
  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState("create");
  const [editing, setEditing] = useState(null);
  const [form] = Form.useForm();

  // Drawer Detail
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detail, setDetail] = useState(null);

  // Apply Select modal
  const [applyModal, setApplyModal] = useState({ open: false, type: null }); // "categories" | "products"
  const [applyOptions, setApplyOptions] = useState([]);
  const [applySelected, setApplySelected] = useState([]);

  // ============== FETCH ALL ==============
  const fetchAll = useCallback(async () => {
    if (!canView) return;
    setLoading(true);
    try {
      const out = [];
      let p = 1;
      const limit = 200;
      while (true) {
        const res = await apiClient.get("/promotions", {
          params: { page: p, limit },
        });
        const items = res.data?.data || [];
        const total = res.data?.pagination?.total ?? items.length;
        out.push(...items);
        if (out.length >= total || items.length === 0) break;
        p += 1;
      }
      setAllPromotions(out);
      setPage(1);
    } catch {
      message.error("Lỗi tải khuyến mãi");
    } finally {
      setLoading(false);
    }
  }, [canView]);

  useEffect(() => {
    fetchAll();
  }, [fetchAll]);

  // ============== FILTER & SORT FE ==============
  const filtered = useMemo(() => {
    let rows = [...allPromotions];

    if (search) {
      const q = search.toLowerCase();
      rows = rows.filter((r) => (r.name || "").toLowerCase().includes(q));
    }

    if (sorter.field && sorter.order) {
      const dir = sorter.order === "ascend" ? 1 : -1;
      const f = sorter.field;
      rows.sort(
        (a, b) =>
          (a[f] ?? "").toString().localeCompare((b[f] ?? "").toString()) * dir
      );
    }

    return rows;
  }, [allPromotions, search, sorter]);

  const pageData = useMemo(() => {
    const start = (page - 1) * pageSize;
    return filtered.slice(start, start + pageSize);
  }, [filtered, page, pageSize]);

  // ============== CRUD ==============
  const openCreate = () => {
    setModalMode("create");
    setEditing(null);
    form.resetFields();
    setModalOpen(true);
  };

  const openEdit = (row) => {
    setModalMode("edit");
    setEditing(row);
    form.setFieldsValue({
      name: row.name,
      discount_percent: row.discount_percent,
      start_date: row.start_date ? dayjs(row.start_date) : null,
      end_date: row.end_date ? dayjs(row.end_date) : null,
    });
    setModalOpen(true);
  };

  const submitForm = async () => {
    const v = await form.validateFields();
    const payload = {
      name: v.name,
      discount_percent: v.discount_percent,
      start_date: v.start_date?.format("YYYY-MM-DD"),
      end_date: v.end_date?.format("YYYY-MM-DD"),
    };

    try {
      if (modalMode === "create") {
        await apiClient.post("/promotions", payload);
        message.success("Đã tạo khuyến mãi");
      } else {
        await apiClient.put(`/promotions/${editing.promotion_id}`, payload);
        message.success("Đã cập nhật khuyến mãi");
      }
      setModalOpen(false);
      fetchAll();
    } catch {
      message.error("Thao tác thất bại");
    }
  };

  const deletePromotion = async (row) => {
    try {
      await apiClient.delete(`/promotions/${row.promotion_id}`);
      message.success("Đã xóa");
      fetchAll();
      if (detail?.promotion_id === row.promotion_id) setDetailOpen(false);
    } catch {
      message.error("Xóa thất bại");
    }
  };

  // ============== DETAIL ==============
  const openDetail = async (row) => {
    setDetailOpen(true);
    setDetailLoading(true);
    try {
      const res = await apiClient.get(`/promotions/${row.promotion_id}`);
      const data = res.data?.data || res.data;

      // Gom dữ liệu thành bảng 3 cột
      const maxLen = Math.max(
        data.categories?.length ?? 0,
        data.products?.length ?? 0,
        data.orders?.length ?? 0
      );
      const combined = [];
      for (let i = 0; i < maxLen; i++) {
        combined.push({
          key: i,
          category: data.categories?.[i] ?? "",
          product: data.products?.[i] ?? "",
          order: data.orders?.[i] ?? "",
        });
      }
      data.combined = combined;
      setDetail(data);
    } catch {
      message.error("Lỗi tải chi tiết");
    } finally {
      setDetailLoading(false);
    }
  };

  // ============== APPLY CATEGORY / PRODUCT ==============
  const openApplyModal = async (type) => {
    setApplyModal({ open: true, type });
    setApplySelected([]);
    try {
      const url = type === "categories" ? "/categories" : "/products";
      const res = await apiClient.get(url, { params: { page: 1, limit: 200 } });
      const items = res.data?.data || [];
      setApplyOptions(
        items.map((i) => ({
          value: type === "categories" ? i.category_id : i.product_id,
          label: i.name,
        }))
      );
    } catch {
      message.error("Lỗi tải danh sách");
    }
  };

  const applyNow = async () => {
    try {
      const type = applyModal.type;
      const url =
        type === "categories"
          ? `/promotions/${detail.promotion_id}/apply-categories`
          : `/promotions/${detail.promotion_id}/apply-products`;
      const body =
        type === "categories"
          ? { category_ids: applySelected }
          : { product_ids: applySelected };
      await apiClient.post(url, body);
      message.success("Áp dụng thành công");
      setApplyModal({ open: false, type: null });
      openDetail(detail); // reload detail
    } catch {
      message.error("Áp dụng thất bại");
    }
  };

  // ============== COLUMNS ==============
  const columns = [
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
    {
      title: "Giảm",
      dataIndex: "discount_percent",
      sorter: true,
      render: (v) => (
        <span style={{ fontWeight: 600, color: "#d46b08" }}>{v}%</span>
      ),
    },

    {
      title: "Bắt đầu",
      dataIndex: "start_date",
      render: (v) => (v ? dayjs(v).format("DD/MM/YYYY") : "—"),
    },
    {
      title: "Kết thúc",
      dataIndex: "end_date",
      render: (v) => (v ? dayjs(v).format("DD/MM/YYYY") : "—"),
    },

    {
      title: "Hành động",
      key: "action",
      render: (_, row) =>
        isAdmin ? (
          <Space>
            <Button onClick={() => openDetail(row)}>Chi tiết</Button>
            <Button onClick={() => openEdit(row)}>Sửa</Button>
            <Popconfirm
              title="Xóa khuyến mãi này?"
              onConfirm={() => deletePromotion(row)}
            >
              <Button danger>Xóa</Button>
            </Popconfirm>
          </Space>
        ) : (
          <Button onClick={() => openDetail(row)}>Chi tiết</Button>
        ),
    },
  ];

  if (!canView) return <div>Bạn không có quyền truy cập trang Khuyến mãi.</div>;

  // ============== RENDER ==============
  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", marginBottom: 16 }}>
        <div
          style={{
            background: "#fff7e6",
            borderRadius: 12,
            padding: 10,
            marginRight: 12,
            fontSize: 24,
          }}
        >
          🎁
        </div>
        <div>
          <h2 style={{ margin: 0 }}>Khuyến mãi</h2>
          <div style={{ fontSize: 13, color: "#888" }}>
            Quản lý chương trình giảm giá & áp dụng
          </div>
        </div>
      </div>

      <Space style={{ marginBottom: 12 }}>
        <Input
          placeholder="Tìm theo tên"
          allowClear
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ width: 260 }}
        />
        {isAdmin && (
          <Button type="primary" onClick={openCreate}>
            Thêm khuyến mãi
          </Button>
        )}
      </Space>

      <Table
        rowKey="promotion_id"
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

      {/* MODAL CREATE / EDIT */}
      <Modal
        title={modalMode === "create" ? "Thêm khuyến mãi" : "Sửa khuyến mãi"}
        open={modalOpen}
        onCancel={() => setModalOpen(false)}
        onOk={submitForm}
      >
        <Form layout="vertical" form={form}>
          <Form.Item name="name" label="Tên" rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item
            name="discount_percent"
            label="Giảm (%)"
            rules={[{ required: true, message: "Nhập %" }]}
          >
            <InputNumber min={1} max={100} style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item
            name="start_date"
            label="Ngày bắt đầu"
            rules={[{ required: true }]}
          >
            <DatePicker style={{ width: "100%" }} />
          </Form.Item>
          <Form.Item
            name="end_date"
            label="Ngày kết thúc"
            rules={[{ required: true }]}
          >
            <DatePicker style={{ width: "100%" }} />
          </Form.Item>
        </Form>
      </Modal>

      {/* DRAWER DETAIL */}
      <Drawer
        title="Chi tiết khuyến mãi"
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        width={900}
      >
        {detailLoading ? (
          "Đang tải..."
        ) : detail ? (
          <>
            <Descriptions bordered size="small" column={2}>
              <Descriptions.Item label="Tên">{detail.name}</Descriptions.Item>
              <Descriptions.Item label="Giảm (%)">
                {detail.discount_percent}
              </Descriptions.Item>
              <Descriptions.Item label="Bắt đầu">
                {detail.start_date}
              </Descriptions.Item>
              <Descriptions.Item label="Kết thúc">
                {detail.end_date}
              </Descriptions.Item>
            </Descriptions>

            <div style={{ margin: "16px 0 8px", fontWeight: 600 }}>
              Danh sách áp dụng
            </div>
            <Table
              rowKey="key"
              columns={[
                { title: "Category", dataIndex: "category" },
                { title: "Product", dataIndex: "product" },
                { title: "Order", dataIndex: "order" },
              ]}
              dataSource={detail.combined}
              pagination={false}
              size="small"
              style={{ marginBottom: 12 }}
            />

            <Space>
              <Button onClick={() => openApplyModal("categories")}>
                Áp dụng Category
              </Button>
              <Button onClick={() => openApplyModal("products")}>
                Áp dụng Product
              </Button>
              <Button
                onClick={() =>
                  navigate(`/orders?promotion_id=${detail.promotion_id}`)
                }
              >
                Xem hóa đơn liên quan
              </Button>
            </Space>
          </>
        ) : null}
      </Drawer>

      {/* APPLY MODAL */}
      <Modal
        title={
          applyModal.type === "categories"
            ? "Áp dụng danh mục"
            : "Áp dụng sản phẩm"
        }
        open={applyModal.open}
        onCancel={() => setApplyModal({ open: false, type: null })}
        onOk={applyNow}
      >
        <Select
          mode="multiple"
          allowClear
          style={{ width: "100%" }}
          placeholder="Chọn nhiều mục"
          options={applyOptions}
          value={applySelected}
          onChange={setApplySelected}
        />
      </Modal>
    </div>
  );
}
