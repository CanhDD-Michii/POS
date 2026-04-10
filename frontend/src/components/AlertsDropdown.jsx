// src/components/AlertsDropdown.jsx
import { useEffect, useRef, useState } from "react";
import { Dropdown, List, Tag, Button, Space, Tooltip } from "antd";
import {
  InfoCircleOutlined,
  WarningOutlined,
  CloseCircleOutlined,
  InboxOutlined,
  ExclamationCircleOutlined,
  ClockCircleOutlined,
  BulbOutlined,
  BellOutlined,
} from "@ant-design/icons";
import apiClient from "../core/api";
import {
  relativeTime,
  formatDateTime,
  severityMeta,
} from "../utils/formatTime";
import { useNavigate } from "react-router-dom";

const typeIcon = {
  low_stock: <InboxOutlined />,
  over_stock: <ExclamationCircleOutlined />,
  promotion_expired: <ClockCircleOutlined />,
  ai_prediction: <BulbOutlined />, // legacy alert type from DB
};

const severityIcon = {
  info: <InfoCircleOutlined />,
  warn: <WarningOutlined />,
  error: <CloseCircleOutlined />,
};

function useBeep() {
  const ctxRef = useRef(null);
  return () => {
    try {
      if (!ctxRef.current)
        ctxRef.current = new (window.AudioContext ||
          window.webkitAudioContext)();
      const ctx = ctxRef.current;
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = "sine";
      o.frequency.value = 880;
      o.connect(g);
      g.connect(ctx.destination);
      g.gain.setValueAtTime(0.0001, ctx.currentTime);
      g.gain.exponentialRampToValueAtTime(0.1, ctx.currentTime + 0.01);
      o.start();
      g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.12);
      o.stop(ctx.currentTime + 0.14);
    } catch (e) {
      console.error("Beep error", e);
    }
  };
}

export default function AlertsDropdown({ onCountChange }) {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState([]); // 10 gần nhất
  const [count, setCount] = useState(0); // unresolved tổng (ước lượng theo trang)
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const beep = useBeep();
  const countRef = useRef(0);

  const fetchAlerts = async () => {
    setLoading(true);
    try {
      // Lấy 10 alert mới nhất; API gốc có pagination → lấy page=1, limit=10
      const res = await apiClient.get("/alerts", {
        params: { page: 1, limit: 10 },
      });
      const data = res?.data?.data || [];
      setItems(data);

      // Ước lượng unresolved từ list (nếu API có param riêng thì đổi sang ?status=unresolved)
      const unresolved = data.filter((x) => !x.is_resolved).length;
      setCount(unresolved);
      if (typeof onCountChange === "function") onCountChange(unresolved);

      // Nếu số lượng tăng → beep
      if (unresolved > countRef.current) {
        beep();
      }
      countRef.current = unresolved;
    } catch (e) {
      // ignore
      console.error("Lỗi tải cảnh báo", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAlerts(); // lần đầu
    const t = setInterval(fetchAlerts, 3000); // mỗi 3s để thông báo nhanh
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleClickItem = (alert) => {
    // Chỉ điều hướng, không đánh dấu đã xử lý
    const type = alert?.type;
    if (type === "low_stock" || type === "over_stock") {
      const pid = alert?.related_product_id;
      if (pid) {
        navigate(`/products?focus=${pid}&alert=1&type=${type}`);
      } else {
        navigate(`/products?alert=1&type=${type}`);
      }
    } else if (type === "promotion_expired") {
      // Không có related_promotion_id trong schema → fallback promotions
      navigate(`/promotions?alert=1&type=${type}`);
    } else if (type === "ai_prediction") {
      const pid = alert?.related_product_id;
      if (pid) {
        navigate(`/products?focus=${pid}&alert=1&type=${type}`);
      } else {
        navigate("/products?alert=1&type=ai_prediction");
      }
    } else {
      navigate("/alerts");
    }
    setOpen(false);
  };
  const severityLabel = {
    low: "Cảnh báo",
    medium: "Khá gấp",
    high: "Khẩn cấp",
    info: "Thông tin",
    warn: "Cảnh báo",
    error: "Nguy hiểm",
  };
  const alertTypeLabel = {
    low_stock: "Sắp hết hàng",
    over_stock: "Tồn kho nhiều",
    promotion_expired: "Khuyến mãi hết hạn",
    ai_prediction: "AI đề xuất",
  };

  const menu = {
    items: [
      {
        key: "header",
        label: (
          <div style={{ fontWeight: 600 }}>
            Cảnh báo gần đây {count > 0 ? `(${count} chưa xử lý)` : ""}
          </div>
        ),
        disabled: true,
      },
      {
        key: "list",
        label: (
          <div
            style={{
              maxHeight: 360,
              width: 380,
              overflowY: "auto",
              paddingRight: 4,
            }}
          >
            <List
              loading={loading}
              dataSource={items}
              locale={{ emptyText: "Không có cảnh báo" }}
              renderItem={(item) => {
                const meta = severityMeta[item?.severity] || severityMeta.low;
                const sIcon = severityIcon[meta.icon];
                const i = typeIcon[item?.type] || <BellOutlined />;

                const createdAt = item?.created_at || item?.updated_at || null;

                return (
                  <List.Item
                    style={{
                      cursor: "pointer",
                      opacity: item.is_resolved ? 0.6 : 1,
                      transition: "background 0.2s",
                    }}
                    onClick={() => handleClickItem(item)}
                  >
                    <List.Item.Meta
                      avatar={<span style={{ fontSize: 18 }}>{i}</span>}
                      title={
                        <Space>
                          <Tag color={meta.color} style={{ marginRight: 4 }}>
                            {sIcon}{" "}
                            {severityLabel[item?.severity] ||
                              item?.severity ||
                              "—"}
                          </Tag>

                          <span
                            style={{
                              fontWeight: 600,
                              color: item.is_resolved ? "#888" : "#222",
                            }}
                          >
                            {alertTypeLabel[item?.type] ||
                              item?.type ||
                              "Cảnh báo"}
                          </span>

                          <span style={{ color: "#999", fontSize: 12 }}>
                            {formatDateTime(createdAt)} (
                            {relativeTime(createdAt)})
                          </span>
                        </Space>
                      }
                      description={
                        <Tooltip title={item?.message}>
                          <div
                            style={{
                              whiteSpace: "nowrap",
                              overflow: "hidden",
                              textOverflow: "ellipsis",
                              maxWidth: 280,
                            }}
                          >
                            {item?.message || "—"}
                          </div>
                        </Tooltip>
                      }
                    />
                  </List.Item>
                );
              }}
            />
            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                marginTop: 8,
              }}
            >
              <Button
                type="link"
                size="small"
                onClick={() => {
                  setOpen(false);
                  navigate("/alerts");
                }}
              >
                Xem tất cả
              </Button>
            </div>
          </div>
        ),
      },
    ],
  };

  return (
    <Dropdown
      menu={menu}
      trigger={["click"]}
      open={open}
      onOpenChange={setOpen}
      placement="bottomRight"
      overlayStyle={{ maxWidth: 420 }}
    >
      <span style={{ display: "inline-flex" }}>
        {/* kích hoạt bằng phần tử bọc bên ngoài */}
        <Button
          type="text"
          icon={<BellOutlined />}
          onClick={(e) => e.preventDefault()}
        />
      </span>
    </Dropdown>
  );
}
