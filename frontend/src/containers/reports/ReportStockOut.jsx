import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Table,
  Button,
  Space,
  DatePicker,
  Input,
  Drawer,
  Descriptions,
  message,
  Tag,
} from "antd";
import {
  SearchOutlined,
  ReloadOutlined,
  PrinterOutlined,
  FilePdfOutlined,
  ShoppingOutlined,
} from "@ant-design/icons";
import moment from "moment";
import apiClient from "../../core/api";
import ProductSelectModal from "../../components/ProductSelectModal";

const { RangePicker } = DatePicker;

/**
 * Stock-out (sales orders) report: same filtering pattern as stock-in.
 */
export default function ReportStockOut() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);
  const [range, setRange] = useState([]);
  const [orderSearch, setOrderSearch] = useState("");
  const [barcodeInput, setBarcodeInput] = useState("");
  const [filterProductId, setFilterProductId] = useState(undefined);
  const [filterProductLabel, setFilterProductLabel] = useState("");
  const [productModalOpen, setProductModalOpen] = useState(false);

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [detail, setDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const fetchList = useCallback(async () => {
    setLoading(true);
    try {
      const params = { limit: 10000 };
      if (range?.length === 2 && range[0] && range[1]) {
        params.start_date = range[0].format("YYYY-MM-DD");
        params.end_date = range[1].format("YYYY-MM-DD");
      }
      if (filterProductId) params.product_id = filterProductId;

      const res = await apiClient.get("/orders", { params });
      setRows(res.data?.data || []);
    } catch {
      message.error("Không tải được danh sách xuất kho");
    } finally {
      setLoading(false);
    }
  }, [range, filterProductId]);

  useEffect(() => {
    fetchList();
  }, [fetchList]);

  const displayRows = useMemo(() => {
    const q = (orderSearch || "").trim().toLowerCase();
    if (!q) return rows;
    return rows.filter(
      (o) =>
        (o.order_number || "").toLowerCase().includes(q) ||
        (o.customer_name || "").toLowerCase().includes(q)
    );
  }, [rows, orderSearch]);

  const openDetail = async (orderNumber) => {
    setDetailLoading(true);
    setDrawerOpen(true);
    try {
      const res = await apiClient.get(`/orders/${orderNumber}`);
      setDetail(res.data?.data || null);
    } catch {
      message.error("Không tải chi tiết hóa đơn");
      setDetail(null);
    } finally {
      setDetailLoading(false);
    }
  };

  const downloadPdf = async (orderNumber) => {
    try {
      const res = await apiClient.get(`/orders/${orderNumber}/invoice`, {
        responseType: "blob",
      });
      const url = window.URL.createObjectURL(res.data);
      const a = document.createElement("a");
      a.href = url;
      a.download = `xuat-${orderNumber}.pdf`;
      a.click();
      window.URL.revokeObjectURL(url);
    } catch {
      message.error("Xuất PDF thất bại");
    }
  };

  const onBarcodeEnter = async () => {
    const code = barcodeInput.trim();
    if (!code) return;
    try {
      const res = await apiClient.get("/orders/scan-barcode", { params: { barcode: code } });
      const p = res.data?.data;
      if (!p?.product_id) throw new Error("empty");
      setFilterProductId(p.product_id);
      setFilterProductLabel(p.name || "");
      message.success(`Lọc theo sản phẩm: ${p.name}`);
    } catch {
      message.warning("Không tìm thấy sản phẩm theo mã vạch");
    }
  };

  const columns = useMemo(
    () => [
      { title: "Mã HĐ", dataIndex: "order_number", width: 180 },
      {
        title: "Ngày",
        dataIndex: "order_date",
        render: (v) => (v ? moment(v).format("DD/MM/YYYY HH:mm") : "—"),
      },
      { title: "Khách", dataIndex: "customer_name" },
      {
        title: "Tổng",
        dataIndex: "total_amount",
        render: (v) => `${Number(v || 0).toLocaleString()} đ`,
      },
      { title: "TT", dataIndex: "status", width: 100, render: (s) => <Tag>{s}</Tag> },
      {
        title: "",
        key: "actions",
        width: 220,
        render: (_, r) => (
          <Space>
            <Button size="small" onClick={() => openDetail(r.order_number)}>
              Chi tiết
            </Button>
            <Button size="small" icon={<FilePdfOutlined />} onClick={() => downloadPdf(r.order_number)}>
              PDF
            </Button>
          </Space>
        ),
      },
    ],
    []
  );

  return (
    <div>
      <h2>Báo cáo — Xuất kho (hóa đơn)</h2>
      <Space wrap style={{ marginBottom: 12 }}>
        <RangePicker value={range} onChange={setRange} allowEmpty={[true, true]} />
        <Input
          placeholder="Mã HĐ / khách…"
          prefix={<SearchOutlined />}
          value={orderSearch}
          onChange={(e) => setOrderSearch(e.target.value)}
          style={{ width: 220 }}
          allowClear
        />
        <Input.Search
          placeholder="Quét mã vạch (Enter)"
          value={barcodeInput}
          onChange={(e) => setBarcodeInput(e.target.value)}
          onSearch={onBarcodeEnter}
          style={{ width: 220 }}
          enterButton
        />
        <Button icon={<ShoppingOutlined />} onClick={() => setProductModalOpen(true)}>
          Tìm sản phẩm
        </Button>
        {filterProductId && (
          <Tag closable onClose={() => { setFilterProductId(undefined); setFilterProductLabel(""); }}>
            SP: {filterProductLabel || filterProductId}
          </Tag>
        )}
        <Button icon={<ReloadOutlined />} onClick={fetchList}>
          Làm mới
        </Button>
      </Space>

      <Table
        rowKey="order_id"
        loading={loading}
        columns={columns}
        dataSource={displayRows}
        pagination={{ pageSize: 15 }}
        onRow={(record) => ({
          onClick: () => openDetail(record.order_number),
          style: { cursor: "pointer" },
        })}
      />

      <Drawer
        title={detail ? `HĐ ${detail.order_number}` : "Chi tiết"}
        width={520}
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        extra={
          detail && (
            <Space className="no-print">
              <Button icon={<PrinterOutlined />} onClick={() => window.print()}>
                In
              </Button>
              <Button type="primary" icon={<FilePdfOutlined />} onClick={() => downloadPdf(detail.order_number)}>
                Xuất hóa đơn PDF
              </Button>
            </Space>
          )
        }
      >
        {detailLoading ? (
          <div>Đang tải…</div>
        ) : detail ? (
          <div id="report-stock-out-print">
            <Descriptions column={1} bordered size="small">
              <Descriptions.Item label="Mã HĐ">{detail.order_number}</Descriptions.Item>
              <Descriptions.Item label="Ngày">
                {detail.order_date ? moment(detail.order_date).format("DD/MM/YYYY HH:mm") : "—"}
              </Descriptions.Item>
              <Descriptions.Item label="Khách">{detail.customer_name || "—"}</Descriptions.Item>
              <Descriptions.Item label="Tổng">{Number(detail.total_amount || 0).toLocaleString()} đ</Descriptions.Item>
              <Descriptions.Item label="Trạng thái">{detail.status}</Descriptions.Item>
            </Descriptions>
            <Table
              style={{ marginTop: 16 }}
              size="small"
              pagination={false}
              rowKey={(r) => `${r.product_id}-${r.quantity}`}
              dataSource={detail.details || []}
              columns={[
                { title: "Sản phẩm", dataIndex: "product_name" },
                { title: "SL", dataIndex: "quantity", width: 64 },
                {
                  title: "Đơn giá",
                  dataIndex: "price",
                  render: (v) => `${Number(v || 0).toLocaleString()} đ`,
                },
                {
                  title: "Thành tiền",
                  render: (_, r) =>
                    `${(Number(r.quantity || 0) * Number(r.price || 0)).toLocaleString()} đ`,
                },
              ]}
            />
          </div>
        ) : null}
      </Drawer>

      <ProductSelectModal
        visible={productModalOpen}
        onClose={() => setProductModalOpen(false)}
        onSelect={(p) => {
          setFilterProductId(p.product_id);
          setFilterProductLabel(p.name);
          setProductModalOpen(false);
          message.info(`Đã chọn sản phẩm lọc: ${p.name}`);
        }}
      />
    </div>
  );
}
