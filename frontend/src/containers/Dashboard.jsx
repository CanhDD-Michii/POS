import { Card, Row, Col } from 'antd';
import { useEffect, useState } from 'react';
import Highcharts from 'highcharts';
import HighchartsReact from 'highcharts-react-official';
import apiClient from '../core/api';

function Dashboard() {
  const [stats, setStats] = useState({ orders: 0, revenue: 0, alerts: 0 });
  const [chartOptions, setChartOptions] = useState({
    title: { text: 'Doanh thu theo tháng' },
    xAxis: { categories: [] },
    series: [{ name: 'Doanh thu', data: [] }],
  });

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const y = new Date().getFullYear();
        const [ordersRes, revenueRes, alertsRes] = await Promise.all([
          apiClient.get('/orders'),
          apiClient.get('/reports/revenue-expense', {
            params: { start_date: `${y}-01-01`, end_date: `${y}-12-31` },
          }),
          apiClient.get('/alerts'),
        ]);
        setStats({
          orders: ordersRes.data.data.length,
          revenue: revenueRes.data.data[0]?.revenue || 0,
          alerts: alertsRes.data.data.length,
        });

        // Dữ liệu mẫu cho biểu đồ
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const revenueData = revenueRes.data.data.map(d => d.revenue || 0);
        setChartOptions({
          title: { text: 'Doanh thu theo tháng' },
          xAxis: { categories: months },
          series: [{ name: 'Doanh thu', data: revenueData }],
          chart: { type: 'line' },
          colors: ['#1890ff'],
        });
      } catch (err) {
        console.error(err);
      }
    };
    fetchStats();
  }, []);

  return (
    <div>
      <h2 style={{ marginBottom: 24 }}>Tổng quan</h2>
      <Row gutter={[16, 16]}>
        <Col span={8}>
          <Card title="Tổng đơn hàng" bordered={false} style={{ borderRadius: 8 }}>
            <h3>{stats.orders}</h3>
          </Card>
        </Col>
        <Col span={8}>
          <Card title="Doanh thu" bordered={false} style={{ borderRadius: 8 }}>
            <h3>{stats.revenue.toLocaleString()} VND</h3>
          </Card>
        </Col>
        <Col span={8}>
          <Card title="Cảnh báo" bordered={false} style={{ borderRadius: 8 }}>
            <h3>{stats.alerts}</h3>
          </Card>
        </Col>
      </Row>
      <Row gutter={[16, 16]} style={{ marginTop: 24 }}>
        <Col span={24}>
          <Card title="Biểu đồ Doanh thu" bordered={false} style={{ borderRadius: 8 }}>
            <HighchartsReact highcharts={Highcharts} options={chartOptions} />
          </Card>
        </Col>
      </Row>
    </div>
  );
}

export default Dashboard;