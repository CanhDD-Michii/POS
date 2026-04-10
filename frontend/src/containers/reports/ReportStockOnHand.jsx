import { useEffect, useMemo, useState } from "react";
import { Table, Input, Space, Button, message, Drawer, Tag } from "antd";
import { SearchOutlined, FileExcelOutlined, FilePdfOutlined, ReloadOutlined } from "@ant-design/icons";
import apiClient from "../../core/api";
import moment from "moment";

function downloadBlob(blob, filename) {
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  window.URL.revokeObjectURL(url);
}

/**
 * On-hand stock list; selecting a row loads inbound/outbound history for that product.
 */
export default function ReportStockOnHand() {
  const [rows, setRows] = useState([]);
  const [q, setQ] = useState("");
  const [loading, setLoading] = useState(false);
  const [mode, setMode] = useState("");

  const [selected, setSelected] = useState(null);
  const [movements, setMovements] = useState([]);
  const [mvLoading, setMvLoading] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);

  const fetchData = async (m = mode) => {
    setLoading(true);
    try {
      const res = await apiClient.get("/reports/inventory", { params: { mode: m || undefined } });
      setRows(res.data?.data || []);
    } catch {
      message.error("Lỗi tải báo cáo tồn");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData("");
  }, []);

  const data = useMemo(() => {
    if (!q) return rows;
    const s = q.toLowerCase();
    return rows.filter((r) => (r.product_name || "").toLowerCase().includes(s));
  }, [rows, q]);

  const openHistory = async (record) => {
    setSelected(record);
    setDrawerOpen(true);
    setMvLoading(true);
    try {
      const res = await apiClient.get(`/reports/product-movements/${record.product_id}`);
      setMovements(res.data?.data || []);
    } catch {
      message.error("Không tải được lịch sử");
      setMovements([]);
    } finally {
      setMvLoading(false);
    }
  };

  const columns = [
    { title: "Sản phẩm", dataIndex: "product_name" },
    { title: "Tồn", dataIndex: "stock", width: 100 },
    { title: "Đã nhập (lọc)", dataIndex: "total_purchased", width: 120 },
    { title: "Đã bán (lọc)", dataIndex: "total_sold", width: 120 },
    { title: "Tồn tối thiểu", dataIndex: "minimum_inventory", width: 120 },
  ];

  const exportCSV = async () => {
    try {
      const payload = { filters: { mode }, displayData: data };
      const res = await apiClient.post("/reports/inventory/csv", payload, { responseType: "blob" });
      downloadBlob(res.data, "bao_cao_ton_kho.csv");
    } catch {
      message.error("Export CSV thất bại");
    }
  };

  const exportPDF = async () => {
    try {
      const payload = { filters: { mode }, displayData: data };
      const res = await apiClient.post("/reports/inventory/export-pdf", payload, { responseType: "blob" });
      downloadBlob(res.data, "bao_cao_ton_kho.pdf");
    } catch {
      message.error("Export PDF thất bại");
    }
  };

  const mvColumns = [
    {
      title: "Loại",
      dataIndex: "direction",
      width: 72,
      render: (d) => (d === "in" ? <Tag color="green">Nhập</Tag> : <Tag color="orange">Xuất</Tag>),
    },
    {
      title: "Thời gian",
      dataIndex: "movement_at",
      render: (v) => (v ? moment(v).format("DD/MM/YYYY HH:mm") : "—"),
    },
    { title: "Chứng từ", dataIndex: "document_ref" },
    { title: "SL", dataIndex: "quantity", width: 72 },
    {
      title: "Đơn giá",
      dataIndex: "unit_price",
      render: (v) => `${Number(v || 0).toLocaleString()} đ`,
    },
    {
      title: "Thành tiền",
      dataIndex: "line_total",
      render: (v) => `${Number(v || 0).toLocaleString()} đ`,
    },
  ];

  return (
    <div>
      <h2>Báo cáo — Tồn kho</h2>
      <p style={{ color: "#666", marginBottom: 12 }}>
        Chọn một dòng để xem lịch sử nhập / xuất theo từng chứng từ.
      </p>
      <Space style={{ marginBottom: 12, flexWrap: "wrap" }}>
        <Input
          placeholder="Tìm theo tên sản phẩm"
          prefix={<SearchOutlined />}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          style={{ width: 260 }}
          allowClear
        />
        <Button icon={<ReloadOutlined />} onClick={() => fetchData(mode)}>
          Làm mới
        </Button>
        <Button onClick={() => { setMode("day"); fetchData("day"); }}>Ngày</Button>
        <Button onClick={() => { setMode("month"); fetchData("month"); }}>Tháng</Button>
        <Button onClick={() => { setMode("year"); fetchData("year"); }}>Năm</Button>
        <Button onClick={() => { setMode("all"); fetchData("all"); }}>Tất cả</Button>
        <Button type="primary" style={{ background: "#52c41a", borderColor: "#52c41a" }} icon={<FileExcelOutlined />} onClick={exportCSV}>
          Xuất CSV
        </Button>
        <Button type="primary" danger icon={<FilePdfOutlined />} onClick={exportPDF}>
          Xuất PDF
        </Button>
      </Space>

      <Table
        rowKey="product_id"
        loading={loading}
        columns={columns}
        dataSource={data}
        pagination={{ pageSize: 20 }}
        onRow={(record) => ({
          onClick: () => openHistory(record),
          style: { cursor: "pointer" },
        })}
      />

      <Drawer
        title={selected ? `Lịch sử: ${selected.product_name}` : "Lịch sử"}
        width={720}
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
      >
        <Table
          rowKey={(r, i) => `${r.document_ref}-${r.movement_at}-${i}`}
          loading={mvLoading}
          columns={mvColumns}
          dataSource={movements}
          pagination={{ pageSize: 12 }}
        />
      </Drawer>
    </div>
  );
}
