import { Menu } from "antd";
import { useNavigate, useLocation } from "react-router-dom";
import { useMemo, useState } from "react";
import { useRecoilValue } from "recoil";
import { userState } from "../core/atoms";
import { ROLE_ADMIN, ROLE_CLIENT } from "../config/roles";
import {
  HomeOutlined,
  ShoppingOutlined,
  TagsOutlined,
  ContainerOutlined,
  ShopOutlined,
  UserOutlined,
  PercentageOutlined,
  ShoppingCartOutlined,
  HistoryOutlined,
  ImportOutlined,
  DatabaseOutlined,
  BarChartOutlined,
  WarningOutlined,
} from "@ant-design/icons";

/** Menu entry: optional `roles` restricts visibility (admin-only vs admin+client). */
function Sidebar() {
  const navigate = useNavigate();
  const location = useLocation();
  const [openKeys, setOpenKeys] = useState([]);
  const user = useRecoilValue(userState);
  const role = user?.role || "guest";

  const baseMenuItems = useMemo(
    () => [
      {
        key: "",
        label: "Tổng quan",
        icon: <HomeOutlined />,
        onClick: () => navigate("/"),
        roles: [ROLE_ADMIN, ROLE_CLIENT],
      },
      {
        key: "inventory",
        label: "Quản lý kho",
        icon: <DatabaseOutlined />,
        roles: [ROLE_ADMIN, ROLE_CLIENT],
        children: [
          { key: "/products", label: "Sản phẩm", icon: <ShoppingOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/categories", label: "Danh mục", icon: <TagsOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/units", label: "Đơn vị", icon: <ContainerOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/suppliers", label: "Nhà cung cấp", icon: <ShopOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/purchases/create", label: "Nhập kho", icon: <ImportOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/purchases", label: "Lịch sử nhập kho", icon: <HistoryOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
        ],
      },
      {
        key: "sales",
        label: "Bán hàng (POS)",
        icon: <ShoppingCartOutlined />,
        roles: [ROLE_ADMIN, ROLE_CLIENT],
        children: [
          { key: "/ordersPOS", label: "POS — Tạo đơn", icon: <ShoppingCartOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/orders", label: "Lịch sử bán hàng", icon: <HistoryOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/customers", label: "Khách hàng", icon: <UserOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/promotions", label: "Khuyến mãi / Voucher", icon: <PercentageOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
        ],
      },
      {
        key: "financials",
        label: "Quản lý thu chi",
        icon: <BarChartOutlined />,
        roles: [ROLE_ADMIN, ROLE_CLIENT],
        children: [
          {
            key: "/financial-transactions",
            label: "Danh sách thu chi",
            icon: <BarChartOutlined />,
            roles: [ROLE_ADMIN, ROLE_CLIENT],
          },
        ],
      },
      {
        key: "reports",
        label: "Báo cáo",
        icon: <BarChartOutlined />,
        roles: [ROLE_ADMIN, ROLE_CLIENT],
        children: [
          { key: "/reports/stock-in", label: "Nhập kho (phiếu)", icon: <ImportOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/reports/stock-out", label: "Xuất kho (HĐ)", icon: <ShoppingCartOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/reports/stock-on-hand", label: "Tồn kho", icon: <DatabaseOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
          { key: "/reports/revenue", label: "Doanh thu (Thu/Chi)", icon: <BarChartOutlined />, roles: [ROLE_ADMIN, ROLE_CLIENT] },
        ],
      },
      {
        key: "/alerts",
        label: "Cảnh báo",
        icon: <WarningOutlined />,
        onClick: () => navigate("/alerts"),
        roles: [ROLE_ADMIN, ROLE_CLIENT],
      },
    ],
    [navigate]
  );

  const filterMenuByRole = (items) => {
    return items
      .filter((item) => !item.roles || item.roles.includes(role))
      .map((item) => {
        const { roles, children, ...rest } = item;
        if (children) {
          const filteredChildren = filterMenuByRole(children);
          if (!filteredChildren.length) return null;
          return { ...rest, children: filteredChildren };
        }
        return rest;
      })
      .filter(Boolean);
  };

  const menuItems = useMemo(
    () => filterMenuByRole(baseMenuItems),
    [baseMenuItems, role]
  );

  const getParentKey = (key) => {
    for (const item of menuItems) {
      if (item.children?.some((child) => child.key === key)) return item.key;
    }
    return null;
  };

  const handleClick = ({ key }) => {
    const parentKey = getParentKey(key);
    if (parentKey) setOpenKeys([parentKey]);
    else setOpenKeys([]);
    if (!menuItems.find((item) => item.key === key)?.children) {
      navigate(key);
    }
  };

  const handleOpenChange = (keys) => {
    setOpenKeys(keys.length > 0 ? [keys[keys.length - 1]] : []);
  };

  return (
    <div
      style={{
        height: "100vh",
        background: "#0f172a",
        color: "#fff",
        display: "flex",
        flexDirection: "column",
        fontSize: "14px",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "16px 18px",
          borderBottom: "1px solid rgba(255,255,255,0.08)",
        }}
      >
        <div
          style={{
            width: 40,
            height: 40,
            borderRadius: "50%",
            background: "rgba(56,161,105,0.15)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 22,
          }}
        >
          🐾
        </div>
        <div style={{ lineHeight: 1.2 }}>
          <div style={{ fontSize: 15, fontWeight: 600 }}>Ngọc Dương Shop</div>
          <div style={{ fontSize: 11, color: "#94a3b8" }}>POS Manager</div>
        </div>
      </div>

      <Menu
        theme="dark"
        mode="inline"
        selectedKeys={[location.pathname]}
        openKeys={openKeys}
        onClick={handleClick}
        onOpenChange={handleOpenChange}
        items={menuItems}
        style={{
          background: "#0f172a",
          borderRight: "none",
          paddingTop: 8,
        }}
      />
    </div>
  );
}

export default Sidebar;
