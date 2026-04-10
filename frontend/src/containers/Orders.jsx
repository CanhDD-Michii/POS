import { useEffect, useMemo, useState, useCallback } from "react";
import {
  Table,
  Input,
  DatePicker,
  Select,
  Space,
  Button,
  Modal,
  Form,
  InputNumber,
  message,
  Drawer,
  Descriptions,
  List,
  Avatar,
  Spin,
} from "antd";
import { SearchOutlined, ReloadOutlined } from "@ant-design/icons";
import { useNavigate } from "react-router-dom";
import moment from "moment";
import apiClient from "../core/api";
import styles from "../styles/Orders.module.css"; // Import CSS
import OnlinePaymentModal from "../components/OnlinePaymentModal";

const { RangePicker } = DatePicker;

export default function Orders() {
  const navigate = useNavigate();
  // const [rows, setRows] = useState([]);
  const [allRows, setAllRows] = useState([]);
  const [loading, setLoading] = useState(false);
  const [pagination, setPagination] = useState({
    page: 1,
    limit: 10,
    total: 0,
  });
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState();
  const [range, setRange] = useState([]);
  

  const [editOpen, setEditOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form] = Form.useForm();

  const [customerModal, setCustomerModal] = useState(false);
  const [paymentModal, setPaymentModal] = useState(false);
  const [promoModal, setPromoModal] = useState(false);
  const [productModal, setProductModal] = useState(false);

  // ======== PAYOS STATE ========
  const [onlineModalOpen, setOnlineModalOpen] = useState(false);
  const [onlinePayment, setOnlinePayment] = useState(null);

  const money = (v) =>
    Number(v || 0).toLocaleString("vi-VN", { maximumFractionDigits: 0 }) + " đ";
  const fmtDate = (v) => (v ? moment(v).format("DD/MM/YYYY HH:mm") : "—");

  const fetchPage = useCallback(async () => {
    setLoading(true);
    try {
      const params = { limit: 10000 }; // hoặc bỏ limit để lấy hết
      if (status) params.status = status;
      if (range?.length === 2) {
        params.start_date = moment(range[0]).format("YYYY-MM-DD");
        params.end_date = moment(range[1]).format("YYYY-MM-DD");
      }
      const res = await apiClient.get("/orders", { params });
      const data = res.data?.data || [];
      setAllRows(data); // ← Lưu toàn bộ
      setPagination((prev) => ({
        ...prev,
        total: data.length,
        page: 1, // reset page khi filter thay đổi
      }));
    } catch {
      message.error("Lỗi tải danh sách hóa đơn");
    } finally {
      setLoading(false);
    }
  }, [status, range]);

  useEffect(() => {
    fetchPage(1);
  }, [fetchPage]);

  // 3. Sửa filtered: lọc trên allRows (toàn bộ), và thêm reset page khi filter
  const filtered = useMemo(() => {
    let result = allRows;

    // Lọc status & range đã xử lý ở server → không cần lọc lại

    // Chỉ lọc search client-side
    if (search) {
      const q = search.toLowerCase();
      result = result.filter(
        (o) =>
          (o.order_number || "").toLowerCase().includes(q) ||
          (o.customer_name || "").toLowerCase().includes(q)
      );
    }

    // Cập nhật total theo kết quả lọc
    setPagination((prev) => ({ ...prev, total: result.length, page: 1 }));

    return result;
  }, [allRows, search]); // status & range đã ở fetch dependency

  useEffect(() => {
    setPagination((prev) => ({ ...prev, page: 1 }));
  }, [search, status, range]);

  const openEdit = async (order_number) => {
    try {
      const res = await apiClient.get(`/orders/${order_number}`);
      const od = res.data.data;
      setEditing(od);
      form.setFieldsValue({
        customer_id: od.customer_id,
        customer_name: od.customer_name,
        payment_method_id: od.payment_method_id,
        payment_method_name: od.payment_method,
        promotion_id: od.promotion_id,
        promotion_name: od.promotion_name,
        status: od.status,
        details: od.details.map((d) => ({
          product_id: d.product_id,
          product_name: d.product_name,
          quantity: d.quantity,
          price: d.price,
        })),
      });
      setEditOpen(true);
    } catch {
      message.error("Không tải được dữ liệu sửa");
    }
  };

  const onSubmitEdit = async (v) => {
    try {
      await apiClient.put(`/orders/${editing.order_number}`, {
        customer_id: v.customer_id,
        payment_method_id: v.payment_method_id,
        promotion_id: v.promotion_id,
        status: v.status,
        details: v.details,
      });
      message.success("Cập nhật thành công");
      setEditOpen(false);
      form.resetFields();
      fetchPage(pagination.page);
    } catch {
      message.error("Cập nhật thất bại");
    }
  };

  const onDelete = (order_number) => {
    Modal.confirm({
      title: "Xoá hóa đơn?",
      content: `Bạn chắc muốn xoá HĐ ${order_number}?`,
      okText: "Xoá",
      cancelText: "Hủy",
      onOk: async () => {
        try {
          await apiClient.delete(`/orders/${order_number}`);
          message.success("Đã xoá");
          fetchPage(pagination.page);
        } catch {
          message.error("Xoá thất bại");
        }
      },
    });
  };

  const retryPayOS = async (order) => {
    try {
      const res = await apiClient.get(
        `/payments/latest?orderNumber=${order.order_number}`
      );
      let pay = res.data?.data;

      if (!pay) {
        message.error("Không phải hóa đơn thanh toán Online");
        return;
      }

      // Chuẩn hóa qr base64
      pay.qrCode = pay.qr_base64 ? `${pay.qr_base64}` : null;

      setOnlinePayment(pay);
      setOnlineModalOpen(true);
    } catch (err) {
      console.error(err);
      message.error("Không tải được thông tin thanh toán");
    }
  };

  const refreshPaymentStatus = async (payCode) => {
    try {
      const res = await apiClient.get(`/payments/${payCode}`);
      const updated = res.data?.data;

      if (!updated) return;

      updated.qrCode = updated.qr_base64;

      setOnlinePayment((prev) => ({
        ...prev,
        status: updated.status,
        qrCode: updated.qrCode,
      }));

      if (updated.status === "completed") {
        message.success("Thanh toán thành công!");
        fetchPage(1);
      }
    } catch {
      message.error("Không thể cập nhật trạng thái");
    }
  };

  const columns = [
    { title: "Số HĐ", dataIndex: "order_number" },
    { title: "Ngày", dataIndex: "order_date", render: fmtDate },
    {
      title: "Khách hàng",
      dataIndex: "customer_name",
      render: (v) => v || "Khách lẻ",
    },
    {
      title: "Tổng tiền",
      dataIndex: "total_amount",
      align: "right",
      render: money,
    },
    {
      title: "Trạng thái",
      dataIndex: "status",
      render: (status) => {
        const statusTranslation = {
          completed: "Hoàn thành",
          pending: "Chờ xử lý",
          cancelled: "Đã huỷ",
        };
        return statusTranslation[status] || status;
      },
    },
    {
      title: "Hành động",
      render: (_, r) => (
        <Space>
          <Button
            className={styles.actionView}
            onClick={() => navigate(`/orders/${r.order_number}`)}
          >
            Xem
          </Button>

          <Button
            className={styles.actionEdit}
            onClick={() => openEdit(r.order_number)}
          >
            Sửa
          </Button>
          <Button
            className={styles.actionDelete}
            onClick={() => onDelete(r.order_number)}
          >
            Xoá
          </Button>

          {r.status === "pending" && (
            <Button type="primary" onClick={() => retryPayOS(r)}>
              Thanh toán lại
            </Button>
          )}
        </Space>
      ),
    },
  ];

  const resetFilters = () => {
    setSearch("");
    setStatus(undefined);
    setRange([]);
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h2 className={styles.title}>Lịch sử hóa đơn</h2>
      </div>

      <div className={styles.filters}>
        <Input
          placeholder="Tìm số HĐ hoặc khách hàng"
          prefix={<SearchOutlined />}
          allowClear
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className={styles.searchInput}
        />
        <Select
          allowClear
          placeholder="Trạng thái"
          value={status}
          onChange={setStatus}
          options={[
            { label: "Hoàn thành", value: "completed" },
            { label: "Chờ xử lý", value: "pending" },
            { label: "Đã huỷ", value: "cancelled" },
          ]}
          className={styles.statusSelect}
        />
        <RangePicker
          value={range}
          onChange={setRange}
          format="DD/MM/YYYY"
          className={styles.datePicker}
        />
        <Button
          icon={<ReloadOutlined />}
          onClick={resetFilters}
          className={styles.resetBtn}
        ></Button>
      </div>

      <div className={styles.tableWrapper}>
        <Table
          rowKey="order_number"
          loading={loading}
          dataSource={filtered.slice(
            (pagination.page - 1) * pagination.limit,
            pagination.page * pagination.limit
          )}
          columns={columns}
          pagination={{
            current: pagination.page,
            pageSize: pagination.limit,
            total: pagination.total, // giờ đúng với data đã lọc
            onChange: (page) => setPagination((prev) => ({ ...prev, page })),
            showSizeChanger: true,
            pageSizeOptions: ["10", "20", "50", "100"],
          }}
          className={styles.table}
        />
      </div>

      

      {/* Modal Edit */}
      {/* ========== MODAL SỬA HÓA ĐƠN – CODE LẠI HOÀN TOÀN ========== */}
      <Modal
        title={editing ? `Sửa HĐ ${editing.order_number}` : "Sửa hóa đơn"}
        open={editOpen}
        onCancel={() => {
          setEditOpen(false);
          form.resetFields();
          setEditing(null);
        }}
        footer={null}
        width={850}
        className={styles.modalTitle}
      >
        <Form
          form={form}
          layout="vertical"
          onFinish={onSubmitEdit}
          className={styles.editModalForm}
        >
          {/* Khách hàng */}
          <Form.Item name="customer_id" hidden>
            <Input />
          </Form.Item>
          <Form.Item shouldUpdate noStyle>
            {() => (
              <Form.Item name="customer_name" label="Khách hàng">
                <Input
                  readOnly
                  placeholder="Chọn khách hàng"
                  suffix={<SearchOutlined />}
                  onClick={() => setCustomerModal(true)}
                  className={styles.formInput}
                />
              </Form.Item>
            )}
          </Form.Item>

          {/* Phương thức thanh toán */}
          <Form.Item name="payment_method_id" hidden>
            <Input />
          </Form.Item>
          <Form.Item shouldUpdate noStyle>
            {() => (
              <Form.Item
                name="payment_method_name"
                label="Phương thức thanh toán"
              >
                <Input
                  readOnly
                  placeholder="Chọn phương thức"
                  suffix={<SearchOutlined />}
                  onClick={() => setPaymentModal(true)}
                  className={styles.formInput}
                />
              </Form.Item>
            )}
          </Form.Item>

          {/* Khuyến mãi */}
          <Form.Item name="promotion_id" hidden>
            <Input />
          </Form.Item>
          <Form.Item name="promotion_name" label="Khuyến mãi">
            <Input
              readOnly
              placeholder="Chọn khuyến mãi (tùy chọn)"
              suffix={<SearchOutlined />}
              onClick={() => setPromoModal(true)}
              className={styles.formInput}
            />
          </Form.Item>

          {/* Trạng thái */}
          <Form.Item
            name="status"
            label="Trạng thái"
            rules={[{ required: true, message: "Chọn trạng thái!" }]}
          >
            <Select
              placeholder="Chọn trạng thái"
              options={[
                { label: "Hoàn thành", value: "completed" },
                { label: "Chờ xử lý", value: "pending" },
                { label: "Đã huỷ", value: "cancelled" },
              ]}
              className={styles.formSelect}
            />
          </Form.Item>

          {/* Danh sách sản phẩm */}
          <div style={{ marginBottom: 16 }}>
            <label
              style={{
                fontWeight: 600,
                color: "#1e293b",
                display: "block",
                marginBottom: 8,
              }}
            >
              Sản phẩm
            </label>
          </div>

          {/* Nút lưu */}
          <Form.Item style={{ marginBottom: 0, textAlign: "right" }}>
            <Space>
              <Button
                onClick={() => {
                  setEditOpen(false);
                  form.resetFields();
                  setEditing(null);
                }}
              >
                Hủy
              </Button>
              <Button type="primary" htmlType="submit">
                Lưu thay đổi
              </Button>
            </Space>
          </Form.Item>
        </Form>
      </Modal>

      {/* Embedded Modals */}
      <CustomerSelectModal
        visible={customerModal}
        onClose={() => setCustomerModal(false)}
        onSelect={(c) =>
          form.setFieldsValue({
            customer_id: c.customer_id,
            customer_name: c.name,
          })
        }
      />
      <PaymentSelectModal
        visible={paymentModal}
        onClose={() => setPaymentModal(false)}
        onSelect={(p) =>
          form.setFieldsValue({
            payment_method_id: p.payment_method_id,
            payment_method_name: p.name,
          })
        }
      />
      <PromotionSelectModal
        visible={promoModal}
        onClose={() => setPromoModal(false)}
        onSelect={(pr) =>
          form.setFieldsValue({
            promotion_id: pr.promotion_id,
            promotion_name: pr.name,
          })
        }
      />
      <ProductSelectModal
        visible={productModal}
        onClose={() => setProductModal(false)}
        onSelect={(p) => {
          const cur = form.getFieldValue("details") || [];
          const newItem = {
            product_id: p.product_id,
            product_name: p.name,
            quantity: 1,
            price: p.price,
          };
          const idx = window.currentDetailIndex;
          if (Number.isInteger(idx)) {
            const next = [...cur];
            next[idx] = { ...newItem, quantity: cur[idx]?.quantity ?? 1 };
            form.setFieldsValue({ details: next });
            window.currentDetailIndex = undefined;
          } else {
            form.setFieldsValue({ details: [...cur, newItem] });
          }
          setProductModal(false);
        }}
      />
      <OnlinePaymentModal
        open={onlineModalOpen}
        data={onlinePayment}
        loading={false}
        onClose={() => setOnlineModalOpen(false)}
        onRefresh={(code) => refreshPaymentStatus(code)}
      />
    </div>
  );
}

/* -------------------------- Embedded Mini Modals -------------------------- */
function CustomerSelectModal({ visible, onClose, onSelect }) {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    if (visible) {
      (async () => {
        setLoading(true);
        try {
          const res = await apiClient.get("/customers", {
            params: { limit: 200 },
          });
          setList(res.data?.data || []);
        } catch {
          message.error("Lỗi tải khách hàng");
        } finally {
          setLoading(false);
        }
      })();
    }
  }, [visible]);
  return (
    <Modal
      open={visible}
      onCancel={onClose}
      footer={null}
      title="Chọn khách hàng"
      className={styles.subModal}
    >
      <List loading={loading} dataSource={list} className={styles.subModalList}>
        {list.map((c) => (
          <List.Item
            key={c.customer_id}
            actions={[
              <Button
                type="primary"
                onClick={() => {
                  onSelect(c);
                  onClose();
                }}
              >
                Chọn
              </Button>,
            ]}
          >
            <List.Item.Meta
              title={c.name}
              description={`${c.phone || "—"} - ${c.email || "—"}`}
            />
          </List.Item>
        ))}
      </List>
    </Modal>
  );
}

function PaymentSelectModal({ visible, onClose, onSelect }) {
  const [list, setList] = useState([]);
  useEffect(() => {
    if (visible)
      apiClient
        .get("/payment-methods")
        .then((r) => setList(r.data?.data || []))
        .catch(() => message.error("Lỗi tải PT thanh toán"));
  }, [visible]);
  return (
    <Modal
      open={visible}
      onCancel={onClose}
      footer={null}
      title="Chọn phương thức thanh toán"
      className={styles.subModal}
    >
      <List dataSource={list} className={styles.subModalList}>
        {list.map((m) => (
          <List.Item
            key={m.payment_method_id}
            actions={[
              <Button
                type="primary"
                onClick={() => {
                  onSelect(m);
                  onClose();
                }}
              >
                Chọn
              </Button>,
            ]}
          >
            <List.Item.Meta title={m.name} description={m.code} />
          </List.Item>
        ))}
      </List>
    </Modal>
  );
}

function PromotionSelectModal({ visible, onClose, onSelect }) {
  const [list, setList] = useState([]);
  useEffect(() => {
    if (visible)
      apiClient
        .get("/promotions")
        .then((r) => setList(r.data?.data || []))
        .catch(() => message.error("Lỗi tải khuyến mãi"));
  }, [visible]);
  return (
    <Modal
      open={visible}
      onCancel={onClose}
      footer={null}
      title="Chọn khuyến mãi"
      className={styles.subModal}
    >
      <List dataSource={list} className={styles.subModalList}>
        {list.map((p) => (
          <List.Item
            key={p.promotion_id}
            actions={[
              <Button
                type="primary"
                onClick={() => {
                  onSelect(p);
                  onClose();
                }}
              >
                Chọn
              </Button>,
            ]}
          >
            <List.Item.Meta
              title={p.name}
              description={`Giảm ${p.discount_percent}% (${p.start_date} to ${p.end_date})`}
            />
          </List.Item>
        ))}
      </List>
    </Modal>
  );
}

function ProductSelectModal({ visible, onClose, onSelect }) {
  const [all, setAll] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (visible)
      (async () => {
        setLoading(true);
        try {
          const res = await apiClient.get("/products", {
            params: { limit: 200 },
          });
          setAll(res.data?.data || []);
        } catch {
          message.error("Không tải được sản phẩm");
        } finally {
          setLoading(false);
        }
      })();
  }, [visible]);

  const filtered = useMemo(() => {
    if (!search) return all;
    const q = search.toLowerCase();
    return all.filter(
      (p) =>
        (p.name || "").toLowerCase().includes(q) ||
        (p.barcode || "").toLowerCase().includes(q)
    );
  }, [all, search]);

  return (
    <Modal
      open={visible}
      onCancel={onClose}
      footer={null}
      title="Chọn sản phẩm"
      width={600}
      className={styles.subModal}
    >
      <Input
        placeholder="Tìm theo tên hoặc barcode..."
        allowClear
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className={styles.subModalSearch}
      />
      <List
        loading={loading}
        dataSource={filtered}
        className={styles.subModalList}
      >
        {filtered.map((p) => (
          <List.Item
            key={p.product_id}
            actions={[
              <Button
                type="primary"
                onClick={() => {
                  onSelect(p);
                  onClose();
                }}
              >
                Chọn
              </Button>,
            ]}
          >
            <List.Item.Meta
              avatar={(() => {
                const imgSrc = p.image_url
                  ? p.image_url.startsWith("http")
                    ? p.image_url
                    : `http://localhost:3000${p.image_url}`
                  : undefined;
                return imgSrc ? (
                  <Avatar
                    shape="square"
                    src={imgSrc}
                    className={styles.productAvatar}
                  />
                ) : (
                  <Avatar shape="square" className={styles.productAvatar}>
                    {p.name?.[0] || "?"}
                  </Avatar>
                );
              })()}
              title={p.name}
              description={
                <>
                  <div>Barcode: {p.barcode || "—"}</div>
                  <div>Giá: {Number(p.price).toLocaleString()} đ</div>
                  <div>Tồn: {p.stock ?? "—"}</div>
                </>
              }
            />
          </List.Item>
        ))}
      </List>
    </Modal>
  );
}
