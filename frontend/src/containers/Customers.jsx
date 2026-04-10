import { useEffect, useState, useCallback, useMemo } from "react";
import {
Table,
Input,
Space,
Button,
Modal,
Form,
message,
Drawer,
Descriptions,
Popconfirm,
DatePicker,
Card,
} from "antd";
import { useRecoilValue } from "recoil";
import { userState } from "../core/atoms";
import apiClient from "../core/api";
import { useNavigate } from "react-router-dom";

export default function Customers() {
const user = useRecoilValue(userState);
const role = user?.role;
const isAdmin = role === "admin";
const canEdit = isAdmin || role === "client";
const navigate = useNavigate();

const [allCustomers, setAllCustomers] = useState([]);
const [search, setSearch] = useState("");
const [sorter, setSorter] = useState({ field: null, order: null });
const [page, setPage] = useState(1);
const [pageSize, setPageSize] = useState(10);
const [loading, setLoading] = useState(false);

const [modalOpen, setModalOpen] = useState(false);
const [modalMode, setModalMode] = useState("create");
const [editing, setEditing] = useState(null);
const [form] = Form.useForm();

const [detailOpen, setDetailOpen] = useState(false);
const [detailLoading, setDetailLoading] = useState(false);
const [detail, setDetail] = useState(null);

const fetchAll = useCallback(async () => {
setLoading(true);
try {
const out = [];
let p = 1;
const limit = 200;


  while (true) {
    const res = await apiClient.get("/customers", {
      params: { page: p, limit },
    });

    const items = res.data?.data || [];
    const total = res.data?.pagination?.total ?? items.length;

    out.push(...items);

    if (out.length >= total || items.length === 0) break;

    p++;
  }

  setAllCustomers(out);
  setPage(1);
} catch {
  message.error("Lỗi tải danh sách khách hàng");
} finally {
  setLoading(false);
}


}, []);

useEffect(() => {
fetchAll();
}, [fetchAll]);

const filtered = useMemo(() => {
let rows = [...allCustomers];


if (search) {
  const q = search.toLowerCase();

  rows = rows.filter(
    (r) =>
      (r.name || "").toLowerCase().includes(q) ||
      (r.phone || "").toLowerCase().includes(q)
  );
}

if (sorter.field && sorter.order) {
  const dir = sorter.order === "ascend" ? 1 : -1;
  const field = sorter.field;

  rows.sort((a, b) => {
    const A = a[field];
    const B = b[field];

    if (typeof A === "string" || typeof B === "string")
      return (A || "").localeCompare(B || "") * dir;

    return ((A ?? 0) - (B ?? 0)) * dir;
  });
}

return rows;


}, [allCustomers, search, sorter]);

const pageData = useMemo(() => {
const start = (page - 1) * pageSize;
return filtered.slice(start, start + pageSize);
}, [filtered, page, pageSize]);

const openCreate = () => {
if (!canEdit) return;


setModalMode("create");
setEditing(null);
form.resetFields();
setModalOpen(true);


};

const openEdit = (row) => {
if (!canEdit) return;


setModalMode("edit");
setEditing(row);

form.setFieldsValue({
  name: row.name,
  phone: row.phone,
  email: row.email,
  gender: row.gender,
  birthday: row.birthday ? dayjs(row.birthday) : null,
  address: row.address,
});

setModalOpen(true);


};

const submitForm = async () => {
const v = await form.validateFields();


try {
  if (modalMode === "create") {
    await apiClient.post("/customers", {
      name: v.name,
      phone: v.phone,
      email: v.email || null,
      gender: v.gender || null,
      birthday: v.birthday ? v.birthday.format("YYYY-MM-DD") : null,
      address: v.address || null,
    });

    message.success("Đã tạo khách hàng");
  } else {
    await apiClient.put(`/customers/${editing.customer_id}`, {
      name: v.name,
      phone: v.phone,
      email: v.email || null,
      gender: v.gender || null,
      birthday: v.birthday ? v.birthday.format("YYYY-MM-DD") : null,
      address: v.address || null,
    });

    message.success("Đã cập nhật khách hàng");
  }

  setModalOpen(false);
  fetchAll();
} catch {
  message.error("Lưu khách hàng thất bại");
}


};

const deleteCustomer = async (row) => {
if (!isAdmin) return;


try {
  await apiClient.delete(`/customers/${row.customer_id}`);

  message.success("Đã xoá khách hàng");

  fetchAll();

  if (detail?.customer_id === row.customer_id) {
    setDetailOpen(false);
  }
} catch {
  message.error("Xoá thất bại");
}


};

const openDetail = async (row) => {
setDetailOpen(true);
await loadDetail(row.customer_id);
};

const loadDetail = useCallback(async (id) => {
setDetailLoading(true);


try {
  const res = await apiClient.get(`/customers/${id}`);
  const data = res.data?.data || res.data;

  data.orders = (data.orders || []).map((o, idx) => ({
    key: idx,
    order_number: o.order_number,
    total_amount: o.total_amount ?? 0,
  }));

  setDetail(data);
} catch {
  message.error("Lỗi tải chi tiết khách hàng");
} finally {
  setDetailLoading(false);
}


}, []);

const columns = [
{
title: "Khách hàng",
dataIndex: "name",
sorter: true,
render: (text, r) => (
<Button type="link" style={{ padding: 0 }} onClick={() => openDetail(r)}>
{text} </Button>
),
},
{
title: "Điện thoại",
dataIndex: "phone",
sorter: true,
},
{
title: "Hành động",
render: (_, row) => ( <Space>
<Button onClick={() => openDetail(row)}>Chi tiết</Button>


      {canEdit && <Button onClick={() => openEdit(row)}>Sửa</Button>}

      {isAdmin && (
        <Popconfirm
          title="Xoá khách hàng này?"
          onConfirm={() => deleteCustomer(row)}
        >
          <Button danger>Xoá</Button>
        </Popconfirm>
      )}
    </Space>
  ),
},


];

return (
<div style={{ padding: 10 }}>
<Card style={{ marginBottom: 16 }}> <Space align="center">
<div
style={{
width: 45,
height: 45,
borderRadius: "50%",
background: "#e6f4ff",
display: "flex",
alignItems: "center",
justifyContent: "center",
fontSize: 22,
}}
>
👤 </div>


      <div>
        <h2 style={{ margin: 0 }}>Khách hàng</h2>
        <div style={{ fontSize: 13, color: "#888" }}>
          Quản lý thông tin và lịch sử mua hàng
        </div>
      </div>
    </Space>
  </Card>

  <Card style={{ marginBottom: 16 }}>
    <Space style={{ width: "100%", justifyContent: "space-between" }}>
      <Input
        placeholder="Tìm theo tên / điện thoại"
        allowClear
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        style={{ width: 300 }}
      />

      {canEdit && (
        <Button type="primary" onClick={openCreate}>
          + Thêm khách hàng
        </Button>
      )}
    </Space>
  </Card>

  <Card>
    <Table
      rowKey="customer_id"
      loading={loading}
      columns={columns}
      dataSource={pageData}
      pagination={{
        current: page,
        pageSize,
        total: filtered.length,
        showSizeChanger: true,
        onChange: (p, ps) => {
          setPage(p);
          setPageSize(ps);
        },
      }}
      onChange={(_, __, s) => {
        if (!s?.field) return;

        setSorter({
          field: s.field,
          order: s.order,
        });
      }}
    />
  </Card>

  <Modal
    title={modalMode === "create" ? "Thêm khách hàng" : "Sửa khách hàng"}
    open={modalOpen}
    onCancel={() => setModalOpen(false)}
    onOk={submitForm}
    okText="Lưu"
  >
    <Form layout="vertical" form={form}>
      <Form.Item
        name="name"
        label="Tên"
        rules={[{ required: true, message: "Nhập tên" }]}
      >
        <Input />
      </Form.Item>

      <Form.Item name="phone" label="Điện thoại">
        <Input />
      </Form.Item>

      <Form.Item name="email" label="Email">
        <Input />
      </Form.Item>

      <Form.Item name="gender" label="Giới tính">
        <Input />
      </Form.Item>

      <Form.Item name="birthday" label="Ngày sinh">
        <DatePicker style={{ width: "100%" }} />
      </Form.Item>

      <Form.Item name="address" label="Địa chỉ">
        <Input />
      </Form.Item>
    </Form>
  </Modal>

  <Drawer
    title="Chi tiết khách hàng"
    open={detailOpen}
    onClose={() => setDetailOpen(false)}
    width={800}
  >
    {detailLoading ? (
      "Đang tải..."
    ) : detail ? (
      <Descriptions bordered size="small" column={2}>
        <Descriptions.Item label="Tên">{detail.name}</Descriptions.Item>
        <Descriptions.Item label="Điện thoại">
          {detail.phone || "-"}
        </Descriptions.Item>
        <Descriptions.Item label="Email">
          {detail.email || "-"}
        </Descriptions.Item>
        <Descriptions.Item label="Giới tính">
          {detail.gender || "-"}
        </Descriptions.Item>
        <Descriptions.Item label="Ngày sinh">
          {detail.birthday
            ? new Date(detail.birthday).toLocaleDateString()
            : "-"}
        </Descriptions.Item>
        <Descriptions.Item label="Địa chỉ" span={2}>
          {detail.address || "-"}
        </Descriptions.Item>
      </Descriptions>
    ) : (
      <div>Không tìm thấy</div>
    )}
  </Drawer>
</div>


);
}
