import { useEffect, useState } from "react";
import { Descriptions, Table, Button, message } from "antd";
import { useNavigate, useParams } from "react-router-dom";
import apiClient from "../core/api";
import moment from "moment";

export default function PurchaseDetail() {
  const { id } = useParams();
  const [data, setData] = useState();
  const navigate = useNavigate();

  useEffect(() => {
    apiClient.get(`/purchases/${id}`).then((res) => setData(res.data.data)).catch(() => {
      message.error("Không tải được chi tiết");
    });
  }, [id]);

  const columns = [
    { title: "Sản phẩm", dataIndex: "product_name" },
    { title: "Nhà cung cấp", dataIndex: "supplier_name" },
    { title: "Số lượng", dataIndex: "quantity" },
    {
      title: "Đơn giá",
      dataIndex: "unit_cost",
      render: (v) => `${v.toLocaleString()}₫`,
    },
  ];

  return data ? (
    <div>
      <Button onClick={() => navigate("/purchases")} style={{ marginBottom: 8 }}>
        Quay lại
      </Button>
      <Descriptions bordered column={2}>
        <Descriptions.Item label="Số phiếu">{data.purchase_number}</Descriptions.Item>
        <Descriptions.Item label="Ngày">{moment(data.purchase_date).format("DD/MM/YYYY")}</Descriptions.Item>
        <Descriptions.Item label="Nhân viên">{data.employee_name}</Descriptions.Item>
        <Descriptions.Item label="Thanh toán">{data.payment_method}</Descriptions.Item>
        <Descriptions.Item label="Trạng thái">{data.status}</Descriptions.Item>
      </Descriptions>
      <Table
        columns={columns}
        dataSource={data.details || []}
        pagination={false}
        rowKey={(r, i) => i}
        style={{ marginTop: 12 }}
      />
    </div>
  ) : null;
}
