import { useEffect, useMemo, useState } from "react";
import {
  Table,
  Input,
  Select,
  Space,
  Button,
  Tag,
  Tooltip,
  Popconfirm,
  message,
} from "antd";
import { SearchOutlined, ReloadOutlined, CheckCircleOutlined, ExclamationCircleOutlined } from "@ant-design/icons";
import apiClient from "../core/api";
import AlertDetail from "./AlertDetail";
import { formatDateTime } from "../utils/formatTime";

// Icon + màu
const typeIcon = {
  low_stock: "⚠️",
  over_stock: "🔥",
  promotion_expired: "🧊",
  ai_prediction: "📌",
};

const severityColor = {
  high: "red",
  medium: "orange",
  low: "gold",
};

export default function Alerts() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);

  // Backend pagination
  const [pagination, setPagination] = useState({ page: 1, limit: 10, total: 0 });

  // FE search/filter
  const [q, setQ] = useState("");
  const [type, setType] = useState(); // gửi lên BE (API có filter type)
  const [resolved, setResolved] = useState(); // filter FE: true/false

  // Detail modal state
  const [detailOpen, setDetailOpen] = useState(false);
  const [selected, setSelected] = useState(null);

  const fetchPage = async (page = 1, limit = pagination.limit, typeParam = type) => {
    setLoading(true);
    try {
      const res = await apiClient.get("/alerts", {
        params: {
          page,
          limit,
          ...(typeParam ? { type: typeParam } : {}),
        },
      });
      const data = res?.data?.data || [];
      const pag = res?.data?.pagination || { page, limit, total: data.length };
      setRows(data);
      setPagination({ page: pag.page, limit: pag.limit, total: Number(pag.total || 0) });
    } catch (e) {
      message.error("Lỗi khi tải danh sách cảnh báo");
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPage(1, pagination.limit, type);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [type]);

  const filtered = useMemo(() => {
    let data = [...rows];
    if (q) {
      const s = q.toLowerCase();
      data = data.filter(
        (r) =>
          (r.message || "").toLowerCase().includes(s) ||
          (r.product_name || "").toLowerCase().includes(s)
      );
    }
    if (resolved !== undefined) {
      data = data.filter((r) => r.is_resolved === resolved);
    }
    return data;
  }, [rows, q, resolved]);

  const resolveAlert = async (record) => {
    if (!record?.alert_id && record?.alert_id !== 0) {
      message.warning("Thiếu alert_id trong dữ liệu list — vui lòng thêm alert_id vào API /alerts");
      return;
    }
    try {
      await apiClient.put(`/alerts/${record.alert_id}/resolve`);
      message.success("Đã đánh dấu 'Đã xử lý'");
      // Làm tươi lại trang hiện tại
      fetchPage(pagination.page, pagination.limit, type);
    } catch (e) {
      message.error("Đánh dấu xử lý thất bại");
      console.error(e);
    }
  };

  const unresolveAlert = async (record) => {
    if (!record?.alert_id && record?.alert_id !== 0) {
      message.warning("Thiếu alert_id trong dữ liệu list");
      return;
    }
    try {
      await apiClient.put(`/alerts/${record.alert_id}/unresolve`);
      message.success("Đã đổi về 'Chưa xử lý'");
      // Làm tươi lại trang hiện tại
      fetchPage(pagination.page, pagination.limit, type);
    } catch (e) {
      message.error("Đổi trạng thái thất bại");
      console.error(e);
    }
  };

  const columns = [
    {
      title: "Loại",
      dataIndex: "type",
      width: 170,
      render: (v) => (
        <span>
          {typeIcon[v] || "🔔"}{" "}
          <Tag>{v || "—"}</Tag>
        </span>
      ),
    },
    {
      title: "Thông điệp",
      dataIndex: "message",
      ellipsis: true,
      render: (text) =>
        text ? (
          <Tooltip title={text}>
            <span>{text}</span>
          </Tooltip>
        ) : (
          "—"
        ),
    },
    {
      title: "Sản phẩm",
      dataIndex: "product_name",
      width: 200,
      render: (v) => v || "—",
    },
    {
      title: "Mức độ",
      dataIndex: "severity",
      width: 120,
      render: (v) => <Tag color={severityColor[v] || "default"}>{v || "—"}</Tag>,
    },
    {
      title: "Trạng thái",
      dataIndex: "is_resolved",
      width: 140,
      render: (v) =>
        v ? <Tag color="green">Đã xử lý</Tag> : <Tag color="red">Chưa xử lý</Tag>,
    },
    {
      title: "Ngày giờ",
      dataIndex: "created_at",
      width: 180,
      render: (v) => formatDateTime(v),
      sorter: (a, b) => {
        const dateA = a.created_at ? new Date(a.created_at).getTime() : 0;
        const dateB = b.created_at ? new Date(b.created_at).getTime() : 0;
        return dateA - dateB;
      },
    },
    {
      title: "Hành động",
      key: "action",
      width: 240,
      render: (_, record) => (
        <Space>
          <Button
            type="link"
            onClick={() => {
              setSelected(record);
              setDetailOpen(true);
            }}
          >
            Chi tiết
          </Button>

          {!record.is_resolved ? (
            <Popconfirm
              title="Đánh dấu đã xử lý cảnh báo này?"
              onConfirm={() => resolveAlert(record)}
              okText="Xác nhận"
              cancelText="Hủy"
            >
              <Button
                type="link"
                icon={<ExclamationCircleOutlined />}
              >
                Đánh dấu xử lý
              </Button>
            </Popconfirm>
          ) : (
            <Popconfirm
              title="Đổi về chưa xử lý cảnh báo này?"
              onConfirm={() => unresolveAlert(record)}
              okText="Xác nhận"
              cancelText="Hủy"
            >
              <Button
                type="link"
                icon={<CheckCircleOutlined />}
              >
                Đổi về chưa xử lý
              </Button>
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ];

  return (
    <div>
      <h2>Quản lý Cảnh báo</h2>

      <Space style={{ marginBottom: 12, flexWrap: "wrap" }}>
        <Input
          placeholder="Tìm theo message / sản phẩm"
          prefix={<SearchOutlined />}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          style={{ width: 280 }}
          allowClear
        />

        <Select
          allowClear
          placeholder="Loại cảnh báo"
          style={{ width: 200 }}
          value={type}
          onChange={setType}
          options={[
            { label: "Sắp hết hàng (low_stock)", value: "low_stock" },
            { label: "Vượt tồn kho (over_stock)", value: "over_stock" },
            { label: "Khuyến mãi hết hạn (promotion_expired)", value: "promotion_expired" },
            { label: "Cảnh báo AI (ai_prediction)", value: "ai_prediction" },
          ]}
        />

        <Select
          allowClear
          placeholder="Trạng thái"
          style={{ width: 160 }}
          value={resolved}
          onChange={setResolved}
          options={[
            { label: "Chưa xử lý", value: false },
            { label: "Đã xử lý", value: true },
          ]}
        />

        <Button
          icon={<ReloadOutlined />}
          onClick={() => fetchPage(1, pagination.limit, type)}
        >
          Làm mới
        </Button>
        <Button
          onClick={() => {
            setQ("");
            setType(undefined);
            setResolved(undefined);
            fetchPage(1, pagination.limit, undefined);
          }}
        >
          Reset bộ lọc
        </Button>
      </Space>

      <Table
        rowKey={(r, i) => r.alert_id ?? i}
        loading={loading}
        columns={columns}
        dataSource={filtered}
        pagination={{
          current: pagination.page,
          pageSize: pagination.limit,
          total: pagination.total,
          onChange: (page, pageSize) => {
            setPagination({ ...pagination, page, limit: pageSize });
            fetchPage(page, pageSize, type);
          },
        }}
      />

      <AlertDetail
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        record={selected}
      />
    </div>
  );
}
