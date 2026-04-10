import { Table, Button, InputNumber, Popconfirm, Space, Typography, message } from "antd";
import { PlusOutlined, MinusOutlined, DeleteOutlined } from "@ant-design/icons";

const { Text } = Typography;

export default function CartTable({ cart, setCart }) {
  const setQty = (pid, qty, stock) => {
    const q = Math.max(1, Math.floor(qty || 1));
    if (stock !== undefined && q > stock) {
      message.warning("Vượt quá tồn kho");
      return;
    }
    setCart((prev) => prev.map((p) => (p.product_id === pid ? { ...p, quantity: q } : p)));
  };

  const inc = (r) => setQty(r.product_id, r.quantity + 1, r.stock);
  const dec = (r) => setQty(r.product_id, r.quantity - 1, r.stock);
  const remove = (pid) => setCart((prev) => prev.filter((p) => p.product_id !== pid));

  const columns = [
    {
      title: "Sản phẩm",
      dataIndex: "name",
      render: (text, r) => (
        <Space direction="vertical" size={0}>
          <Text strong>{text}</Text>
          <Text type="secondary" style={{ fontSize: 12 }}>
            {r.barcode ? `Barcode: ${r.barcode}` : ""}
          </Text>
        </Space>
      ),
    },
    {
      title: "Giá",
      dataIndex: "price",
      render: (v) => <Text>{Number(v).toLocaleString()} đ</Text>,
      width: 110,
      align: "right",
    },
    {
      title: "SL",
      dataIndex: "quantity",
      width: 160,
      render: (_, r) => (
        <Space>
          <Button size="large" onClick={() => dec(r)} icon={<MinusOutlined />} />
          <InputNumber
            size="large"
            min={1}
            value={r.quantity}
            onChange={(v) => setQty(r.product_id, v, r.stock)}
          />
          <Button size="large" onClick={() => inc(r)} icon={<PlusOutlined />} />
        </Space>
      ),
    },
    {
      title: "Thành tiền",
      width: 130,
      align: "right",
      render: (_, r) => (
        <Text strong>{(Number(r.price) * Number(r.quantity)).toLocaleString()} đ</Text>
      ),
    },
    {
      title: "",
      width: 64,
      align: "center",
      render: (_, r) => (
        <Popconfirm title="Xóa sản phẩm này?" onConfirm={() => remove(r.product_id)}>
          <Button size="large" danger icon={<DeleteOutlined />} />
        </Popconfirm>
      ),
    },
  ];

  return (
    <Table
      rowKey="product_id"
      columns={columns}
      dataSource={cart}
      pagination={false}
      size="middle"
    />
  );
}
