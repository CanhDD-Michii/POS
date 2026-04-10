import { useEffect, useState } from "react";
import { Card, Col, DatePicker, Row, Space, Statistic, Button, message } from "antd";
import { ReloadOutlined } from "@ant-design/icons";
import moment from "moment";
import apiClient from "../../core/api";

const { RangePicker } = DatePicker;

/**
 * Revenue report: totals of completed income vs expense from financial_transactions.
 */
export default function ReportRevenue() {
  const [range, setRange] = useState(() => {
    const start = moment().startOf("month");
    const end = moment().endOf("month");
    return [start, end];
  });
  const [totalIn, setTotalIn] = useState(0);
  const [totalOut, setTotalOut] = useState(0);
  const [loading, setLoading] = useState(false);

  const fetchSummary = async () => {
    setLoading(true);
    try {
      const params = {};
      if (range?.length === 2 && range[0] && range[1]) {
        params.start_date = range[0].format("YYYY-MM-DD");
        params.end_date = range[1].format("YYYY-MM-DD");
      }
      const res = await apiClient.get("/reports/revenue-summary", { params });
      const d = res.data?.data || {};
      setTotalIn(Number(d.total_in || 0));
      setTotalOut(Number(d.total_out || 0));
    } catch {
      message.error("Không tải được báo cáo doanh thu");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSummary();
  }, []);

  return (
    <div>
      <h2>Báo cáo — Doanh thu (Thu / Chi)</h2>
      <Space style={{ marginBottom: 24 }} wrap>
        <RangePicker value={range} onChange={setRange} allowEmpty={[true, true]} />
        <Button type="primary" icon={<ReloadOutlined />} loading={loading} onClick={fetchSummary}>
          Áp dụng khoảng thời gian
        </Button>
      </Space>

      <Row gutter={[16, 16]}>
        <Col xs={24} md={12}>
          <Card loading={loading}>
            <Statistic
              title="Tổng tiền thu (giao dịch thu — hoàn tất)"
              value={totalIn}
              precision={0}
              suffix="đ"
              valueStyle={{ color: "#3f8600" }}
            />
          </Card>
        </Col>
        <Col xs={24} md={12}>
          <Card loading={loading}>
            <Statistic
              title="Tổng tiền chi (giao dịch chi — hoàn tất)"
              value={totalOut}
              precision={0}
              suffix="đ"
              valueStyle={{ color: "#cf1322" }}
            />
          </Card>
        </Col>
      </Row>
    </div>
  );
}
