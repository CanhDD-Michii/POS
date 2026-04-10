import { useState, useEffect, useMemo, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import {
  Button,
  Card,
  Space,
  message,
  Spin,
  DatePicker,
  Upload,
  Typography,
  Alert,
} from "antd";
import {
  SaveOutlined,
  ShoppingCartOutlined,
  FileSearchOutlined,
  InboxOutlined,
} from "@ant-design/icons";

import apiClient from "../core/api";
import moment from "moment";

import PurchaseItemsTable from "../components/PurchaseItemsTable";
import ProductSelectModalPurchase from "../components/ProductSelectModalPurchase";
import PaymentModal from "../components/PaymentModal";

const { Text, Paragraph } = Typography;

function newLineId() {
  return globalThis.crypto?.randomUUID?.() || `line-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

export default function PurchaseCreate() {
  const { id } = useParams();
  const navigate = useNavigate();

  const [initialLoad, setInitialLoad] = useState(!!id);
  const [saving, setSaving] = useState(false);
  const [purchaseDate, setPurchaseDate] = useState(moment());
  const [items, setItems] = useState([]);

  const [modalVisible, setModalVisible] = useState(false);
  const [pickForLineId, setPickForLineId] = useState(null);
  const [pmModalVisible, setPmModalVisible] = useState(false);
  const [aiImporting, setAiImporting] = useState(false);
  const [aiMeta, setAiMeta] = useState(null);

  useEffect(() => {
    if (!id) return;
    setInitialLoad(true);

    apiClient
      .get(`/purchases/${id}`)
      .then((res) => {
        const p = res.data.data;
        setPurchaseDate(moment(p.purchase_date));
        setItems(
          (p.details || []).map((d, idx) => ({
            line_id: `edit-${d.product_id}-${idx}`,
            product_id: d.product_id,
            name: d.product_name,
            quantity: d.quantity,
            unit_cost: d.unit_cost,
          }))
        );
      })
      .catch(() => message.error("Không tải được phiếu nhập"))
      .finally(() => setInitialLoad(false));
  }, [id]);

  const totalAmount = useMemo(
    () => items.reduce((sum, i) => sum + Number(i.quantity || 0) * Number(i.unit_cost || 0), 0),
    [items]
  );

  const closeProductModal = useCallback(() => {
    setPickForLineId(null);
    setModalVisible(false);
  }, []);

  const addProduct = (p) => {
    if (pickForLineId) {
      setItems((prev) =>
        prev.map((x) =>
          x.line_id === pickForLineId
            ? {
                ...x,
                product_id: p.product_id,
                name: p.name,
                needs_manual_product: false,
                unit_cost:
                  Number(x.unit_cost) > 0
                    ? x.unit_cost
                    : Number(p.cost_price || 0),
              }
            : x
        )
      );
      closeProductModal();
      return;
    }

    setItems((prev) => {
      const exists = prev.find((x) => x.product_id === p.product_id);
      if (exists) {
        return prev.map((x) =>
          x.product_id === p.product_id
            ? { ...x, quantity: x.quantity + 1 }
            : x
        );
      }
      return [
        ...prev,
        {
          line_id: newLineId(),
          product_id: p.product_id,
          name: p.name,
          quantity: 1,
          unit_cost: Number(p.cost_price || 0),
        },
      ];
    });
    closeProductModal();
  };

  /** PDF/DOCX → OpenAI → append parsed lines (user reviews before save). */
  const handleAiBeforeUpload = async (file) => {
    setAiImporting(true);
    setAiMeta(null);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const res = await apiClient.post("/purchases/import/preview", fd, {
        headers: { "Content-Type": "multipart/form-data" },
      });
      const d = res.data?.data;
      if (!d?.lines?.length) {
        message.warning("Không trích xuất được dòng sản phẩm nào");
        return false;
      }
      (d.warnings || []).forEach((w) => message.warning(w));
      setAiMeta(d.extraction || null);
      const newLines = d.lines.map((l, i) => ({
        line_id: `ai-${Date.now()}-${i}`,
        product_id: l.matched_product_id,
        name: l.resolved_product_name || l.raw_product_name,
        raw_product_name: l.raw_product_name,
        quantity: l.quantity,
        unit_cost: l.unit_cost,
        match_confidence: l.match_confidence,
        needs_manual_product: l.needs_manual_product,
      }));
      setItems((prev) => [...prev, ...newLines]);
      message.success(`Đã thêm ${newLines.length} dòng từ phiếu (AI). Kiểm tra và gắn SP nếu thiếu.`);
    } catch (err) {
      message.error(err.response?.data?.error || "Phân tích phiếu thất bại");
    } finally {
      setAiImporting(false);
    }
    return false;
  };

  const savePurchase = () => {
    if (!items.length) return message.warning("Chưa có sản phẩm");
    if (items.some((i) => !i.product_id)) {
      message.warning("Còn dòng chưa gắn sản phẩm trong kho — bấm «Gắn SP» hoặc xóa dòng.");
      return;
    }
    setPmModalVisible(true);
  };

  const handlePaymentSelect = async (methodId) => {
    if (!methodId) return;

    try {
      setSaving(true);

      const body = {
        payment_method_id: methodId,
        status: "completed",
        purchase_date: purchaseDate.format("YYYY-MM-DD"),
        details: items.map((i) => ({
          product_id: i.product_id,
          quantity: i.quantity,
          unit_cost: i.unit_cost,
        })),
      };

      if (id) {
        await apiClient.put(`/purchases/${id}`, body);
        message.success("Đã cập nhật phiếu nhập");
      } else {
        await apiClient.post(`/purchases`, body);
        message.success("Đã tạo phiếu nhập");
      }

      setPmModalVisible(false);
      navigate("/purchases");
    } catch (err) {
      console.error(err);
      message.error("Lưu phiếu thất bại");
    } finally {
      setSaving(false);
    }
  };

  if (initialLoad) return <Spin tip="Đang tải phiếu nhập..." />;

  return (
    <div style={{ padding: 16 }}>
      <div
        style={{
          marginBottom: 16,
          padding: "12px 16px",
          background: "#ffffff",
          borderRadius: 8,
          border: "1px solid #e5e7eb",
        }}
      >
        <h2 style={{ margin: 0, color: "#2d3748" }}>
          {id ? "Sửa phiếu nhập" : "Tạo phiếu nhập mới"}
        </h2>
        <p style={{ margin: "4px 0 0", color: "#718096", fontSize: 13 }}>
          Thủ công, hoặc import PDF/DOCX — AI đọc phiếu và khớp sản phẩm trong kho (cần OPENAI_API_KEY trên server).
        </p>
      </div>

      <Space direction="vertical" size="middle" style={{ width: "100%" }}>
        <div
          style={{
            padding: 12,
            background: "#ffffff",
            borderRadius: 8,
            border: "1px solid #e5e7eb",
          }}
        >
          <Space align="center">
            <span style={{ fontWeight: 500 }}>Ngày nhập:</span>
            <DatePicker
              value={purchaseDate}
              disabled
              onChange={setPurchaseDate}
              format="DD/MM/YYYY HH:mm"
            />
          </Space>
        </div>

        <Card
          title={
            <Space>
              <FileSearchOutlined />
              <span>Import phiếu (PDF / DOCX) — OpenAI</span>
            </Space>
          }
          bordered
          style={{ borderRadius: 8 }}
        >
          <Paragraph type="secondary" style={{ marginBottom: 12 }}>
            Tải file có lớp văn bản (không phải ảnh scan). Kết quả được thêm vào bảng bên dưới; bạn chỉnh SL/đơn giá và
            gắn sản phẩm trước khi lưu — lúc đó mới ghi DB.
          </Paragraph>
          <Upload.Dragger
            name="file"
            multiple={false}
            showUploadList={false}
            accept=".pdf,.docx,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            beforeUpload={handleAiBeforeUpload}
            disabled={aiImporting}
          >
            <p className="ant-upload-drag-icon">
              <InboxOutlined />
            </p>
            <p className="ant-upload-text">Kéo thả PDF hoặc DOCX vào đây</p>
            <p className="ant-upload-hint">Chỉ phân tích — chưa lưu phiếu</p>
          </Upload.Dragger>
          {aiMeta && (
            <Alert
              style={{ marginTop: 12 }}
              type="info"
              showIcon
              message={
                <span>
                  Nguồn: {aiMeta.source} · Gửi model {aiMeta.text_sent_length}/{aiMeta.text_length} ký tự
                  {aiMeta.truncated ? " (đã cắt bớt)" : ""} · Catalog {aiMeta.catalog_size} SP · {aiMeta.model}
                </span>
              }
            />
          )}
        </Card>

        <Card title="Danh sách sản phẩm" bordered style={{ borderRadius: 8 }}>
          <Space wrap style={{ marginBottom: 12 }}>
            <Button
              icon={<ShoppingCartOutlined />}
              onClick={() => {
                setPickForLineId(null);
                setModalVisible(true);
              }}
            >
              Chọn sản phẩm
            </Button>
            <Text type="secondary">Dòng từ AI chưa khớp: bấm «Gắn SP» trên bảng.</Text>
          </Space>

          <PurchaseItemsTable
            items={items}
            setItems={setItems}
            onAssignProduct={(lineId) => {
              setPickForLineId(lineId);
              setModalVisible(true);
            }}
          />

          <Card
            style={{
              width: 340,
              marginLeft: "auto",
              textAlign: "right",
              marginTop: 16,
              borderRadius: 8,
              border: "1px solid #e5e7eb",
              background: "#f7fafc",
            }}
            title="Tổng cộng"
          >
            <h3 style={{ margin: "0 0 8px", color: "#2f855a" }}>
              {totalAmount.toLocaleString("vi-VN")} ₫
            </h3>

            <Button
              type="primary"
              icon={<SaveOutlined />}
              loading={saving}
              style={{
                width: "100%",
                background: "#38a169",
                border: "none",
              }}
              onClick={savePurchase}
            >
              {id ? "Cập nhật phiếu nhập" : "Lưu phiếu nhập"}
            </Button>
          </Card>
        </Card>
      </Space>

      <ProductSelectModalPurchase
        open={modalVisible}
        onClose={closeProductModal}
        onSelect={addProduct}
      />

      <PaymentModal
        visible={pmModalVisible}
        onOk={handlePaymentSelect}
        onCancel={() => setPmModalVisible(false)}
      />
    </div>
  );
}
