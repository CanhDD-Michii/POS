import { useEffect, useState } from "react";
import {
  Modal,
  Form,
  Input,
  InputNumber,
  Select,
  Upload,
  Button,
  message,
  Space,
} from "antd";
import { UploadOutlined } from "@ant-design/icons";
import apiClient from "../core/api";

const BASE_URL = "http://localhost:3000";

export default function ProductForm({ open, onClose, onSuccess, editing }) {
  const [form] = Form.useForm();
  const [fileList, setFileList] = useState([]);
  const [categories, setCategories] = useState([]);
  const [suppliers, setSuppliers] = useState([]);
  const [units, setUnits] = useState([]);

  // ======== ✅ HÀM TẠO BARCODE NGẪU NHIÊN EAN-13 ======== //
  const generateBarcodeEAN13 = () => {
    let code = "";
    for (let i = 0; i < 12; i++) {
      code += Math.floor(Math.random() * 10);
    }
    const digits = code.split("").map(Number);
    const oddSum = digits
      .filter((_, i) => i % 2 === 0)
      .reduce((sum, n) => sum + n, 0);
    const evenSum = digits
      .filter((_, i) => i % 2 === 1)
      .reduce((sum, n) => sum + n, 0);
    const total = oddSum * 3 + evenSum;
    const checksum = (10 - (total % 10)) % 10;
    const finalCode = code + checksum;
    form.setFieldValue("barcode", finalCode);
  };

  // Load category & supplier
  const fetchOptions = async () => {
    try {
      const resC = await apiClient.get("/categories");
      const resS = await apiClient.get("/suppliers");
      setCategories(resC.data?.data || []);
      setSuppliers(resS.data?.data || []);
    } catch {
      message.error("Lỗi tải dữ liệu danh mục / NCC");
    }
  };

  useEffect(() => {
    if (open) fetchOptions();
  }, [open]);

  useEffect(() => {
    const fetchUnits = async () => {
      try {
        const res = await apiClient.get("/units", {
          params: { page: 1, limit: 500 },
        });
        setUnits(res.data?.data || []);
      } catch {
        message.error("Lỗi tải đơn vị tính");
      }
    };

    fetchUnits();
  }, []);

  // Khi mở form sửa
  useEffect(() => {
    if (editing) {
      form.setFieldsValue(editing);
      if (editing.image_url) {
        setFileList([
          {
            uid: "-1",
            name: "Ảnh hiện tại",
            status: "done",
            url: `${BASE_URL}${editing.image_url}`,
          },
        ]);
      }
    } else {
      form.resetFields();
      setFileList([]);
    }
  }, [editing, form]);

  // Submit
  const submitForm = async () => {
    try {
      const values = await form.validateFields();
      const fd = new FormData();

      // append field
      for (const key of Object.keys(values)) {
        fd.append(key, values[key]);
      }

      // append image
      if (fileList.length > 0 && fileList[0].originFileObj) {
        fd.append("image", fileList[0].originFileObj);
      } else if (editing?.image_url) {
        fd.append("image_url", editing.image_url);
      }

      let res;
      if (editing) {
        res = await apiClient.put(`/products/${editing.product_id}`, fd, {
          headers: { "Content-Type": "multipart/form-data" },
        });
        message.success("Đã cập nhật sản phẩm");
      } else {
        // eslint-disable-next-line no-unused-vars
        res = await apiClient.post("/products", fd, {
          headers: { "Content-Type": "multipart/form-data" },
        });
        message.success("Đã thêm sản phẩm");
      }

      onSuccess();
    } catch (err) {
      console.error(err);
      message.error("Lưu thất bại");
    }
  };

  return (
    <Modal
      open={open}
      title={editing ? "Sửa sản phẩm" : "Thêm sản phẩm"}
      onCancel={onClose}
      onOk={submitForm}
      okText="Lưu"
      destroyOnClose
    >
      <Form layout="vertical" form={form} style={{ paddingTop: 4 }}>
        {/* 🔹 THÔNG TIN SẢN PHẨM */}
        <div style={{ fontWeight: 600, marginBottom: 8, fontSize: 15 }}>
          📝 Thông tin sản phẩm
        </div>

        <Form.Item
          name="name"
          label="Tên sản phẩm"
          rules={[{ required: true, message: "Nhập tên sản phẩm" }]}
        >
          <Input placeholder="Nhập tên sản phẩm" />
        </Form.Item>

        <Form.Item label="Barcode">
          <Space>
            <Form.Item
              name="barcode"
              noStyle
              rules={[{ required: true, message: "Nhập hoặc tạo barcode" }]}
            >
              <Input placeholder="Barcode" style={{ width: 200 }} />
            </Form.Item>
            <Button onClick={generateBarcodeEAN13}>Tạo</Button>
          </Space>
        </Form.Item>

        <Form.Item name="description" label="Mô tả">
          <Input.TextArea
            rows={2}
            placeholder="Mô tả sản phẩm (không bắt buộc)"
          />
        </Form.Item>

        {/* 🔹 GIÁ – CHI PHÍ */}
        <div style={{ fontWeight: 600, margin: "12px 0 8px", fontSize: 15 }}>
          💵 Giá & Chi phí
        </div>

        <Space style={{ width: "100%" }} size="middle">
          <Form.Item
            name="price"
            label="Giá bán"
            rules={[{ required: true, message: "Nhập giá bán" }]}
            style={{ flex: 1 }}
          >
            <InputNumber
              min={0}
              style={{ width: "100%" }}
              placeholder="Ví dụ: 120000"
            />
          </Form.Item>

          <Form.Item
            name="cost_price"
            label="Giá vốn"
            rules={[{ required: true, message: "Nhập giá vốn" }]}
            style={{ flex: 1 }}
          >
            <InputNumber
              min={0}
              style={{ width: "100%" }}
              placeholder="Ví dụ: 80000"
            />
          </Form.Item>
        </Space>

        {/* 🔹 TỒN KHO */}
        <div style={{ fontWeight: 600, margin: "12px 0 8px", fontSize: 15 }}>
          📦 Tồn kho
        </div>

        <Space style={{ width: "100%" }} size="middle">
          <Form.Item
            name="stock"
            label="Tồn hiện tại"
            rules={[{ required: true, message: "Nhập tồn kho" }]}
            style={{ flex: 1 }}
          >
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>

          <Form.Item
            name="minimum_inventory"
            label="Tồn tối thiểu"
            rules={[{ required: true, message: "Nhập tồn tối thiểu" }]}
            style={{ flex: 1 }}
          >
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>

          <Form.Item
            name="maximum_inventory"
            label="Tồn tối đa"
            rules={[{ required: true, message: "Nhập tồn tối đa" }]}
            style={{ flex: 1 }}
          >
            <InputNumber min={0} style={{ width: "100%" }} />
          </Form.Item>
        </Space>

        {/* 🔹 DANH MỤC – NCC – ĐƠN VỊ */}
        <div style={{ fontWeight: 600, margin: "12px 0 8px", fontSize: 15 }}>
          🏷 Danh mục – Nhà cung cấp – Đơn vị
        </div>

        <Space style={{ width: "100%" }} size="middle">
          <Form.Item
            name="category_id"
            label="Danh mục"
            rules={[{ required: true, message: "Chọn danh mục" }]}
            style={{ flex: 1 }}
          >
            <Select
              allowClear
              placeholder="Chọn danh mục"
              options={categories.map((c) => ({
                value: c.category_id,
                label: c.name,
              }))}
            />
          </Form.Item>

          <Form.Item
            name="supplier_id"
            label="Nhà cung cấp"
            rules={[{ required: true, message: "Chọn nhà cung cấp" }]}
            style={{ flex: 1 }}
          >
            <Select
              allowClear
              placeholder="Chọn nhà cung cấp"
              options={suppliers.map((s) => ({
                value: s.supplier_id,
                label: s.name,
              }))}
            />
          </Form.Item>

          <Form.Item
            name="unit_id"
            label="Đơn vị"
            rules={[{ required: true, message: "Chọn đơn vị" }]}
            style={{ flex: 1 }}
          >
            <Select
              allowClear
              placeholder="Đơn vị tính"
              options={units.map((u) => ({
                value: u.unit_id,
                label: u.name,
              }))}
            />
          </Form.Item>
        </Space>

        {/* 🔹 ẢNH */}
        <div style={{ fontWeight: 600, margin: "14px 0 8px", fontSize: 15 }}>
          🖼 Ảnh minh họa
        </div>

        <Form.Item>
          <Upload
            fileList={fileList}
            beforeUpload={() => false}
            onChange={({ fileList: fl }) => setFileList(fl.slice(-1))}
            maxCount={1}
            accept="image/*"
            listType="picture"
          >
            <Button icon={<UploadOutlined />}>Chọn ảnh</Button>
          </Upload>
        </Form.Item>
      </Form>
    </Modal>
  );
}
