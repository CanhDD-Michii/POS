import { useState, useEffect, useMemo } from "react";
import {
  Table,
  Input,
  Button,
  DatePicker,
  Select,
  Drawer,
  Space,
  message,
  Popconfirm,
  Typography,
  Card,
  Descriptions,
} from "antd";
import {
  PlusOutlined,
  SearchOutlined,
  PrinterOutlined,
} from "@ant-design/icons";
import { useNavigate } from "react-router-dom";
import apiClient from "../core/api";
import moment from "moment";
import OnlinePaymentModal from "../components/OnlinePaymentModal";

const { Text } = Typography;

export default function Purchases() {
  const navigate = useNavigate();

  // List state
  const [data, setData] = useState([]);
  const [pagination] = useState({
    page: 1,
    limit: 10,
    total: 0,
  });
  const [loading, setLoading] = useState(false);

  // Filters
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState();
  const [range, setRange] = useState([]);

  // Drawer state
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [drawerMode, setDrawerMode] = useState("view"); // view | edit
  const [current, setCurrent] = useState(null);
  const [items, setItems] = useState([]); // read-only in O1 (giữ để submit lại details nếu backend yêu cầu)
  const [clientPagination, setClientPagination] = useState({
    page: 1,
    limit: 10,
  });

  // Edit fields
  const [methods, setMethods] = useState([]);
  const [editStatus, setEditStatus] = useState();
  const [editPaymentMethod, setEditPaymentMethod] = useState();

  // Online payment modal
  // const [onlineModalOpen, setOnlineModalOpen] = useState(false);
  // const [onlinePayment, setOnlinePayment] = useState(null);
  // const [onlineLoading, setOnlineLoading] = useState(false);

  // ===== Load list =====
  const fetchPurchases = async () => {
    // Bỏ param page
    setLoading(true);
    try {
      const res = await apiClient.get("/purchases"); // Giả sử backend cho fetch all, hoặc thêm param limit=0/all
      setData(res.data?.data || []);
      // Không cần pagination từ server nữa
    } catch {
      message.error("Lỗi tải danh sách phiếu nhập");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPurchases();
    apiClient.get("/payment-methods").then((res) => {
      setMethods(res.data?.data || []);
    });
  }, []);

  // ===== Filtered data =====
  const filteredData = useMemo(() => {
    const q = (search || "").toLowerCase();
    return (data || []).filter((item) => {
      const matchSearch =
        (item?.purchase_number || "").toLowerCase().includes(q) ||
        (item?.employee_name || "").toLowerCase().includes(q);
      const matchStatus = !status || item?.status === status;
      const inRange =
        !range ||
        range.length !== 2 ||
        !range[0] ||
        !range[1] ||
        moment(item?.purchase_date).isBetween(range[0], range[1], null, "[]");
      return matchSearch && matchStatus && inRange;
    });
  }, [data, search, status, range]);

  useEffect(() => {
    setClientPagination((prev) => ({ ...prev, page: 1 }));
  }, [search, status, range]);

  // ===== Open view/edit =====
  const openDetail = async (id, mode = "view") => {
    try {
      const res = await apiClient.get(`/purchases/${id}`);
      const p = res.data?.data;
      if (!p) throw new Error("Không có dữ liệu phiếu");

      setCurrent(p);
      // Lưu lại details (để hiển thị & nếu PUT backend yêu cầu details)
      setItems(
        (p.details || []).map((d) => ({
          product_id: d.product_id,
          name: d.product_name,
          supplier_name: d.supplier_name,
          quantity: Number(d.quantity || 0),
          unit_cost: Number(d.unit_cost || 0),
        }))
      );

      // Edit fields
      setEditPaymentMethod(p.payment_method_id ?? undefined);
      setEditStatus(p.status ?? undefined);

      setDrawerMode(mode);
      setDrawerOpen(true);
    } catch (e) {
      console.error(e);
      message.error("Không tải được chi tiết phiếu");
    }
  };

  // ===== Delete =====
  const handleDelete = async (id) => {
    try {
      await apiClient.delete(`/purchases/${id}`);
      message.success("Đã xoá phiếu nhập");
      fetchPurchases(pagination.page);
    } catch {
      message.error("Xoá phiếu thất bại");
    }
  };

  // ===== Save (O1: chỉ sửa status + payment_method) =====
  // Để tương thích backend (kể cả khi PUT yêu cầu details),
  // ta sẽ gửi kèm lại details hiện tại (không đổi).
  const handleSave = async () => {
    if (!current) return;

    // details gửi lại y nguyên
    const details = (items || []).map((i) => ({
      product_id: i.product_id,
      quantity: Number(i.quantity || 0),
      unit_cost: Number(i.unit_cost || 0),
    }));

    if (!details.length) {
      // theo Option Y: không cho phiếu rỗng
      return message.warning("Phiếu phải có ít nhất 1 sản phẩm");
    }

    try {
      await apiClient.put(`/purchases/${current.purchase_id}`, {
        payment_method_id: editPaymentMethod ?? null,
        status: editStatus ?? null,
        details, // kèm lại để backend nào yêu cầu cũng ok
      });
      message.success("Đã cập nhật phiếu nhập");
      setDrawerOpen(false);
      // reload list
      fetchPurchases(pagination.page);
    } catch (e) {
      console.error(e);
      message.error("Cập nhật thất bại");
    }
  };

  // ===== Thanh toán lại (PayOS) =====
  // const handleRetryPayment = async (purchaseId) => {
  //   try {
  //     // 1. Lấy FULL thông tin phiếu nhập trước (để có purchase_number + total)
  //     const res = await apiClient.get(`/purchases/${purchaseId}`);
  //     const p = res.data?.data;

  //     if (!p) return message.error("Không tải được phiếu nhập");

  //     const purchaseNumber = p.purchase_number;

  //     // Tính tổng tiền
  //     const totalAmount = (p.details || []).reduce(
  //       (sum, i) => sum + Number(i.quantity) * Number(i.unit_cost),
  //       0
  //     );

  //     setOnlineLoading(true);

  //     // 2. Gọi PayOS tạo QR + link thanh toán
  //     await apiClient.post("/payments/payos", {
  //       purchaseNumber,
  //       amount: totalAmount,
  //       description: `Pay-${purchaseNumber}`.substring(0, 25),
  //       type: "purchase",
  //       returnUrl: `${window.location.origin}/purchases`,
  //       cancelUrl: `${window.location.origin}/purchases`,
  //     });

  //     // 3. Lấy payment mới nhất từ DB
  //     const resLatest = await apiClient.get(
  //       `/payments/latest?purchaseNumber=${purchaseNumber}`
  //     );

  //     let pay = resLatest.data?.data;
  //     if (!pay) return message.error("Không tìm thấy payment");

  //     // Chuẩn hóa QR
  //     const qr = pay.qr_base64 || pay.qrCode || pay.data?.qrCode || null;
  //     pay.qrCode = qr;

  //     // 4. Mở modal luôn
  //     setOnlinePayment(pay);
  //     setOnlineModalOpen(true);
  //   } catch (err) {
  //     console.error(err);
  //     message.error("Không tạo được thanh toán online");
  //   } finally {
  //     setOnlineLoading(false);
  //   }
  // };

  // ===== Derived total (for view) =====
  const total = useMemo(() => {
    return Number(
      (items || []).reduce(
        (s, i) => s + Number(i.quantity || 0) * Number(i.unit_cost || 0),
        0
      ) || 0
    );
  }, [items]);

  // ===== Table columns (list) =====
  const columns = [
    { title: "Số phiếu", dataIndex: "purchase_number" },
    {
      title: "Ngày",
      dataIndex: "purchase_date",
      render: (d) => (d ? moment(d).format("DD/MM/YYYY HH:mm") : "—"),
    },
    { title: "Người tạo", dataIndex: "employee_name" },
    {
      title: "Tổng tiền",
      dataIndex: "total_amount",
      render: (v) => `${Number(v || 0).toLocaleString()}₫`,
      align: "right",
    },
    {
      title: "Trạng thái",
      dataIndex: "status",
      render: (status) => {
        const statusTranslation = {
          completed: "Hoàn thành",
          pending: "Chờ xử lý",
          cancelled: "Hủy",
        };
        return statusTranslation[status] || status; // Nếu không tìm thấy, trả lại giá trị gốc
      },
    },
    {
      title: "Hành động",
      render: (_, record) => (
        <Space>
          <Button
            type="link"
            onClick={() => openDetail(record.purchase_id, "view")}
          >
            Chi tiết
          </Button>
          <Button
            type="link"
            onClick={() => openDetail(record.purchase_id, "edit")}
          >
            Sửa
          </Button>
          <Popconfirm
            title="Xoá phiếu nhập này?"
            onConfirm={() => handleDelete(record.purchase_id)}
          >
            <Button type="link" danger>
              Xoá
            </Button>
          </Popconfirm>
          {/* {record.status === "pending" && (
            <Button
              type="link"
              style={{ color: "#1677ff", fontWeight: 500 }}
              onClick={() => handleRetryPayment(record.purchase_id)}
            >
              Thanh toán online
            </Button>
          )} */}
        </Space>
      ),
    },
  ];

  // ===== Product columns (in drawer readonly for O1) =====
  const productCols = [
    { title: "Sản phẩm", dataIndex: "name" },
    { title: "Nhà cung cấp", dataIndex: "supplier_name" },
    {
      title: "SL",
      dataIndex: "quantity",
      align: "right",
      render: (v) => Number(v || 0),
      width: 80,
    },
    {
      title: "Giá nhập",
      dataIndex: "unit_cost",
      align: "right",
      render: (v) => `${Number(v || 0).toLocaleString()}₫`,
      width: 120,
    },
    {
      title: "Thành tiền",
      align: "right",
      render: (_, r) =>
        `${Number(
          Number(r?.quantity || 0) * Number(r?.unit_cost || 0) || 0
        ).toLocaleString()}₫`,
      width: 140,
    },
  ];

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
        <h2 style={{ margin: 0, color: "#2d3748" }}>📥 Danh sách phiếu nhập</h2>
        <Text type="secondary">
          Quản lý nhập kho thuốc, vật tư và sản phẩm thú y
        </Text>
      </div>

      {/* FILTER */}
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
            placeholder="🔍 Số phiếu / người tạo"
            prefix={<SearchOutlined />}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ width: 260 }}
          />
          <Select
            allowClear
            placeholder="Trạng thái"
            value={status}
            onChange={setStatus}
            options={[
              { label: "Hoàn thành", value: "completed" },
              { label: "Chờ xử lý", value: "pending" },
              { label: "Huỷ", value: "cancelled" },
            ]}
            style={{ width: 160 }}
          />
          <DatePicker.RangePicker onChange={setRange} />
          <Button
            type="primary"
            icon={<PlusOutlined />}
            style={{ background: "#38a169", border: "none" }}
            onClick={() => navigate("/purchases/create")}
          >
            Tạo phiếu nhập
          </Button>
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
          rowKey="purchase_id"
          loading={loading}
          columns={columns}
          dataSource={filteredData.slice(
            (clientPagination.page - 1) * clientPagination.limit,
            clientPagination.page * clientPagination.limit
          )}
          pagination={{
            current: clientPagination.page,
            pageSize: clientPagination.limit,
            total: filteredData.length, // Total sau lọc
            onChange: (p, ps) =>
              setClientPagination({
                page: p,
                limit: ps || clientPagination.limit,
              }),
          }}
        />
      </div>

      {/* DRAWER */}
      <Drawer
        width={720}
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        title={
          drawerMode === "edit" ? "✏️ Sửa phiếu nhập" : "📄 Chi tiết phiếu nhập"
        }
        extra={
          drawerMode === "edit" ? (
            <Button
              type="primary"
              style={{ background: "#38a169", border: "none" }}
              onClick={handleSave}
            >
              Lưu
            </Button>
          ) : (
            <Button icon={<PrinterOutlined />} onClick={() => window.print()}>
              In phiếu
            </Button>
          )
        }
      >
        {current ? (
          <>
            <Descriptions bordered size="small" column={2}>
              <Descriptions.Item label="Số phiếu">
                {current.purchase_number || "—"}
              </Descriptions.Item>
              <Descriptions.Item label="Ngày">
                {current.purchase_date
                  ? moment(current.purchase_date).format("DD/MM/YYYY")
                  : "—"}
              </Descriptions.Item>
              <Descriptions.Item label="Người tạo" span={2}>
                {current.employee_name || "—"}
              </Descriptions.Item>

              {drawerMode === "edit" ? (
                <>
                  <Descriptions.Item label="Thanh toán" span={2}>
                    <Select
                      style={{ width: "100%" }}
                      value={editPaymentMethod}
                      onChange={setEditPaymentMethod}
                      options={methods.map((m) => ({
                        label: m.name,
                        value: m.payment_method_id,
                      }))}
                    />
                  </Descriptions.Item>
                  <Descriptions.Item label="Trạng thái" span={2}>
                    <Select
                      style={{ width: 240 }}
                      value={editStatus}
                      onChange={setEditStatus}
                      options={[
                        { label: "Hoàn thành", value: "completed" },
                        { label: "Chờ xử lý", value: "pending" },
                        { label: "Huỷ", value: "cancelled" },
                      ]}
                    />
                  </Descriptions.Item>
                </>
              ) : (
                <>
                  <Descriptions.Item label="Thanh toán" span={2}>
                    {current.payment_method_name || "—"}
                  </Descriptions.Item>
                  <Descriptions.Item label="Trạng thái" span={2}>
                    {current.status || "—"}
                  </Descriptions.Item>
                </>
              )}
            </Descriptions>

            <Table
              style={{ marginTop: 12 }}
              rowKey="product_id"
              columns={productCols}
              dataSource={items}
              pagination={false}
              size="small"
            />

            <Card style={{ marginTop: 12, textAlign: "right" }}>
              <h3>Tổng cộng: {Number(total || 0).toLocaleString()}₫</h3>
            </Card>
          </>
        ) : (
          "Đang tải..."
        )}
      </Drawer>
    </div>
  );
}
