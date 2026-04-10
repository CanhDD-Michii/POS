import { useRecoilState } from "recoil";
import { userState } from "../core/atoms";
import { Dropdown, Avatar, Space, Badge, Breadcrumb } from "antd";
import { UserOutlined, LogoutOutlined, HomeOutlined } from "@ant-design/icons";
import { useNavigate, useLocation } from "react-router-dom";
import { useState } from "react";
import AlertsDropdown from "../components/AlertsDropdown";
import { UPLOADS_ORIGIN } from "../config/constants";

function Topbar() {
  const [user, setUser] = useRecoilState(userState);
  const navigate = useNavigate();
  const location = useLocation();
  const [alertCount, setAlertCount] = useState(0);

  const buildAvatarUrl = (url) => {
    if (!url) return null;
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    return `${UPLOADS_ORIGIN}${url}`;
  };

  const handleLogout = () => {
    setUser(null);
    localStorage.removeItem("token");
    localStorage.removeItem("user");
    navigate("/login");
  };

  const menuItems = [
    {
      key: "logout",
      label: "Đăng xuất",
      icon: <LogoutOutlined />,
      onClick: handleLogout,
    },
  ];

  const pathTitle = {
    "/": "Tổng quan",
    "/products": "Sản phẩm",
    "/categories": "Danh mục",
    "/units": "Đơn vị",
    "/suppliers": "Nhà cung cấp",
    "/customers": "Khách hàng",
    "/promotions": "Khuyến mãi",
    "/orders": "Lịch sử bán hàng",
    "/ordersPOS": "POS — Tạo đơn",
    "/purchases": "Lịch sử nhập kho",
    "/purchases/create": "Tạo phiếu nhập",
    "/financial-transactions": "Quản lý thu chi",
    "/alerts": "Cảnh báo",
    "/settings": "Cài đặt",
    "/reports/stock-in": "Báo cáo nhập kho",
    "/reports/stock-out": "Báo cáo xuất kho",
    "/reports/stock-on-hand": "Báo cáo tồn kho",
    "/reports/revenue": "Báo cáo doanh thu",
  };

  const breadcrumbItems = [
    {
      title: <HomeOutlined />,
      href: "/",
      onClick: () => navigate("/"),
    },
    ...(() => {
      if (location.pathname.startsWith("/orders/") && location.pathname !== "/orders") {
        const orderId = location.pathname.split("/").pop();
        return [
          { title: "Lịch sử bán hàng", onClick: () => navigate("/orders") },
          { title: `Hóa đơn ${orderId}` },
        ];
      }
      const t = pathTitle[location.pathname];
      if (t) return [{ title: t }];
      return [];
    })(),
  ];

  return (
    <div
      className="topbar-container"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "10px 16px",
        background: "linear-gradient(90deg, #f7fafc 0%, #eef7f2 100%)",
        borderBottom: "1px solid #e5e7eb",
        position: "relative",
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 12,
          top: "50%",
          transform: "translateY(-50%)",
          fontSize: 60,
          opacity: 0.15,
          pointerEvents: "none",
        }}
      >
        🐾
      </div>

      <Breadcrumb
        items={breadcrumbItems.map((b) => ({
          title: <span style={{ color: "#2d3748", fontWeight: 500 }}>{b.title}</span>,
          onClick: b.onClick,
        }))}
        style={{ margin: "0 16px", zIndex: 1 }}
      />

      <div className="topbar-right" style={{ display: "flex", alignItems: "center", gap: 12, zIndex: 1 }}>
        <Badge count={alertCount}>
          <AlertsDropdown onCountChange={setAlertCount} />
        </Badge>

        <Dropdown menu={{ items: menuItems }} trigger={["click"]}>
          <Space
            style={{
              cursor: "pointer",
              padding: "4px 8px",
              borderRadius: 6,
              transition: "background 0.2s",
            }}
          >
            <Avatar
              src={buildAvatarUrl(user?.avatar)}
              icon={<UserOutlined />}
              size="large"
              style={{ backgroundColor: "#c6f6d5", color: "#2f855a" }}
            />
            <span style={{ color: "#2d3748", fontWeight: 500 }}>{user?.username}</span>
            <span style={{ fontSize: 12, color: "#718096" }}>({user?.role})</span>
          </Space>
        </Dropdown>
      </div>
    </div>
  );
}

export default Topbar;
