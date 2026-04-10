import { Table, InputNumber, Popconfirm, Button, Tag, Space } from "antd";
import { DeleteOutlined, WarningOutlined } from "@ant-design/icons";

/**
 * Purchase line editor. Each row uses stable line_id (supports duplicate product_id work-in-progress and AI rows without product_id).
 * onAssignProduct(lineId) — open product picker to bind warehouse product to an unmatched AI row.
 */
export default function PurchaseItemsTable({ items, setItems, onAssignProduct }) {
  const update = (lineId, key, value) => {
    setItems((prev) =>
      prev.map((i) => (i.line_id === lineId ? { ...i, [key]: value } : i))
    );
  };

  const remove = (lineId) => {
    setItems((prev) => prev.filter((i) => i.line_id !== lineId));
  };

  const columns = [
    {
      title: "Sản phẩm",
      dataIndex: "name",
      width: "40%",
      render: (v, r) => (
        <span>
          {!r.product_id && (
            <Tag color="warning" icon={<WarningOutlined />} style={{ marginRight: 6 }}>
              Chưa gắn SP
            </Tag>
          )}
          {v}
          {r.raw_product_name && r.raw_product_name !== r.name && (
            <div style={{ fontSize: 11, color: "#888" }}>Phiếu: {r.raw_product_name}</div>
          )}
        </span>
      ),
    },
    {
      title: "Số lượng",
      dataIndex: "quantity",
      render: (v, r) => (
        <InputNumber
          min={1}
          value={v}
          onChange={(val) => update(r.line_id, "quantity", val ?? 1)}
        />
      ),
    },
    {
      title: "Đơn giá (₫)",
      dataIndex: "unit_cost",
      render: (v, r) => (
        <InputNumber
          min={0}
          value={v}
          onChange={(val) => update(r.line_id, "unit_cost", val ?? 0)}
        />
      ),
    },
    {
      title: "Thành tiền (₫)",
      render: (_, r) =>
        (Number(r.quantity || 0) * Number(r.unit_cost || 0)).toLocaleString("vi-VN"),
    },
    {
      title: "Hành động",
      width: 140,
      render: (_, r) => (
        <Space size={4} wrap>
          {!r.product_id && typeof onAssignProduct === "function" && (
            <Button size="small" type="primary" ghost onClick={() => onAssignProduct(r.line_id)}>
              Gắn SP
            </Button>
          )}
          <Popconfirm title="Xóa dòng này?" onConfirm={() => remove(r.line_id)}>
            <Button type="text" danger icon={<DeleteOutlined />} />
          </Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <Table
      dataSource={items}
      columns={columns}
      rowKey="line_id"
      pagination={false}
      bordered
      size="small"
    />
  );
}
