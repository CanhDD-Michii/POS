// src/pages/FinancialTransactions.jsx
import { useEffect, useMemo, useState } from "react";
import {
  Table,
  Input,
  DatePicker,
  Select,
  Space,
  Button,
  Tag,
  Popconfirm,
  message,
  Card,
} from "antd";
import {
  PlusOutlined,
  SearchOutlined,
  EyeOutlined,
  EditOutlined,
  DeleteOutlined,
  ReloadOutlined,
} from "@ant-design/icons";
import dayjs from "dayjs";
import apiClient from "../core/api";
import FinancialTransactionModal from "../components/FinancialTransactionModal";
import FinancialTransactionDetail from "./FinancialTransactionDetail";

const { RangePicker } = DatePicker;
const TYPE_COLORS = { income: "green", expense: "red", other: "default" };

function fmtCurrency(v) {
  return `${Number(v || 0).toLocaleString("vi-VN")} ₫`;
}
function fmtDate(d) {
  return d ? dayjs(d).add(7, "hour").format("DD/MM/YYYY") : "—"; // Fix hiển thị ngày local +7h
}

export default function FinancialTransactions() {
  const [allData, setAllData] = useState([]);
  const [loading, setLoading] = useState(false);

  const [pagination, setPagination] = useState({
    page: 1,
    limit: 10,
    total: 0,
  });

  // Filters
  const [search, setSearch] = useState("");
  const [type, setType] = useState();
  const [status, setStatus] = useState();
  const [range, setRange] = useState([]);

  // Modal & Detail
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailId, setDetailId] = useState(null);

  // Fetch toàn bộ data, chỉ lọc type + status ở server
  const fetchAll = async () => {
    setLoading(true);
    try {
      const params = {
        limit: 10000, // Lấy hết
        ...(type ? { type } : {}),
        ...(status ? { status } : {}),
      };
      const res = await apiClient.get("/financial-transactions", { params });
      const data = res.data?.data || [];
      setAllData(data);
      setPagination((prev) => ({
        ...prev,
        total: data.length,
        page: 1,
      }));
    } catch {
      message.error("Lỗi tải giao dịch tài chính");
    } finally {
      setLoading(false);
    }
  };

  // Refetch khi type hoặc status thay đổi
  useEffect(() => {
    fetchAll();
  }, [type, status]); // eslint-disable-line react-hooks/exhaustive-deps

  // Reset page về 1 khi search hoặc range thay đổi
  useEffect(() => {
    setPagination((prev) => ({ ...prev, page: 1 }));
  }, [search, range]);

  // Client-side filtering cho search + date range (with timezone fix)
  const filtered = useMemo(() => {
    let data = [...allData];

    // Lọc search (cải thiện bằng cách gộp fields)
    if (search) {
      const q = search.toLowerCase().trim();
      data = data.filter((r) => {
        const fields = [
          r.payment_method_name || "",
          r.status || "",
          r.type || "",
          r.payer_receiver_name || "",
          r.original_document_number || "",
          r.or || "",
          r.order_number || "",
          r.purchase_number || "",
          String(r.transaction_id || ""),
          r.employee_name || "",
        ]
          .join(" ")
          .toLowerCase();
        return fields.includes(q);
      });
    }

    // Lọc ngày - fix timezone +7 cho Việt Nam
    if (range?.length === 2 && range[0] && range[1]) {
      const startLocal = dayjs(range[0]).format("YYYY-MM-DD");
      const endLocal = dayjs(range[1]).format("YYYY-MM-DD");

      data = data.filter((r) => {
        if (!r.transaction_date) return false;
        // Chuyển UTC về local date string
        const localDate = dayjs(r.transaction_date)
          .add(7, "hour")
          .format("YYYY-MM-DD");
        return localDate >= startLocal && localDate <= endLocal;
      });
    }

    // Cập nhật total
    setPagination((prev) => ({ ...prev, total: data.length }));

    return data;
  }, [allData, search, range]);

  const remove = async (record) => {
    try {
      await apiClient.delete(
        `/financial-transactions/${record.transaction_id}`
      );
      message.success("Đã xoá giao dịch");
      fetchAll();
    } catch {
      message.error("Xoá thất bại");
    }
  };

  const openCreate = () => {
    setEditing(null);
    setModalOpen(true);
  };
  const openEdit = (record) => {
    setEditing(record);
    setModalOpen(true);
  };
  const openDetail = (record) => {
    setDetailId(record.transaction_id);
    setDetailOpen(true);
  };

  const columns = [
    {
      title: "Loại",
      dataIndex: "type",
      width: 110,
      render: (v) => (
        <Tag color={TYPE_COLORS[v] || "default"}>
          {v === "income" ? "Thu" : v === "expense" ? "Chi" : "Khác"}
        </Tag>
      ),
    },
    {
      title: "Số tiền",
      dataIndex: "amount",
      align: "right",
      width: 140,
      render: (v) => fmtCurrency(v),
    },
    {
      title: "Ngày",
      dataIndex: "transaction_date",
      width: 130,
      render: (v) => fmtDate(v),
    },
    { title: "PT Thanh toán", dataIndex: "payment_method_name" },
    {
      title: "Trạng thái",
      dataIndex: "status",
      width: 130,
      render: (status) => {
        const statusTranslation = {
          completed: "Hoàn thành",
          pending: "Chờ xử lý",
          cancelled: "Đã huỷ",
        };
        return statusTranslation[status] || status; // Nếu không tìm thấy, trả lại giá trị gốc
      },
    },
    {
      title: "Người trả/nhận",
      dataIndex: "payer_receiver_name",
      render: (v) => v || "Khách lẻ",
    },
    {
      title: "Chứng từ",
      width: 200,
      render: (_, r) =>
        r.original_document_number ||
        r.or ||
        r.order_number ||
        r.purchase_number ||
        "Không có",
    },
    {
      title: "Hành động",
      width: 200,
      render: (_, r) => (
        <Space>
          <Button icon={<EyeOutlined />} onClick={() => openDetail(r)}>
            Chi tiết
          </Button>
          <Button icon={<EditOutlined />} onClick={() => openEdit(r)}>
            Sửa
          </Button>
          <Popconfirm title="Xoá giao dịch này?" onConfirm={() => remove(r)}>
            <Button danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <div>
      <div style={{ marginBottom: 16 }}>
        <h2 style={{ marginBottom: 4 }}>Quản lý thu chi</h2>
        <div style={{ fontSize: 13, color: "#64748b" }}>
          Theo dõi thu – chi – phiếu nhập – hóa đơn bán hàng
        </div>
      </div>

      <Card
        size="small"
        style={{
          marginBottom: 16,
          borderRadius: 8,
          background: "#fafafa",
        }}
      >
        <Space wrap>
          <Input
            placeholder="🔎 Tìm (số chứng từ, người trả/nhận, phương thức...)"
            prefix={<SearchOutlined />}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ width: 320 }}
          />

          <Select
            allowClear
            placeholder="📌 Loại giao dịch"
            value={type}
            onChange={setType}
            style={{ width: 160 }}
            options={[
              { label: "Thu", value: "income" },
              { label: "Chi", value: "expense" },
              { label: "Khác", value: "other" },
            ]}
          />

          <Select
            allowClear
            placeholder="📄 Trạng thái"
            value={status}
            onChange={setStatus}
            style={{ width: 160 }}
            options={[
              { label: "Hoàn thành", value: "completed" },
              { label: "Chờ xử lý", value: "pending" },
              { label: "Đã hủy", value: "cancelled" },
            ]}
          />

          <RangePicker
            value={range}
            onChange={setRange}
            placeholder={["Từ ngày", "Đến ngày"]}
            style={{ width: 240 }}
          />

          <Button
            icon={<ReloadOutlined />}
            onClick={() => {
              setSearch("");
              setType(undefined);
              setStatus(undefined);
              setRange([]);
            }}
          ></Button>

          <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
            Thêm giao dịch
          </Button>
        </Space>
      </Card>

      <Table
        rowKey="transaction_id"
        loading={loading}
        columns={columns}
        dataSource={filtered.slice(
          (pagination.page - 1) * pagination.limit,
          pagination.page * pagination.limit
        )}
        pagination={{
          current: pagination.page,
          pageSize: pagination.limit,
          total: pagination.total,
          showSizeChanger: true,
          pageSizeOptions: ["10", "20", "50", "100"],
          onChange: (page, pageSize) => {
            setPagination((prev) => ({
              ...prev,
              page,
              limit: pageSize || prev.limit,
            }));
          },
        }}
      />

      {modalOpen && (
        <FinancialTransactionModal
          open={modalOpen}
          editing={editing}
          onClose={() => setModalOpen(false)}
          onSuccess={() => {
            setModalOpen(false);
            fetchAll();
          }}
        />
      )}

      {detailOpen && (
        <FinancialTransactionDetail
          open={detailOpen}
          id={detailId}
          onClose={() => setDetailOpen(false)}
        />
      )}
    </div>
  );
}
