import { useEffect } from "react";
import { Routes, Route, useNavigate, Outlet, useLocation } from "react-router-dom";
import { Layout, Spin, theme } from "antd";
import { useRecoilValue } from "recoil";
import { userState } from "./core/atoms";
import Sidebar from "./components/Sidebar";
import Topbar from "./components/Topbar";
import Login from "./containers/Login";
import Products from "./containers/Products";
import Settings from "./containers/Settings";
import Categories from "./containers/Categories";
import Units from "./containers/Units";
import Suppliers from "./containers/Suppliers";
import Customers from "./containers/Customers";
import Promotions from "./containers/Promotions";
import Orders from "./containers/Orders";
import OrderPOS from "./containers/OrderPOS";
import OrderDetail from "./containers/OrderDetail";
import Purchases from "./containers/Purchases";
import PurchaseDetail from "./containers/PurchaseDetail";
import PurchaseCreate from "./containers/PurchaseCreate";
import FinancialTransactions from "./containers/FinancialTransactions";
import FinancialTransactionDetail from "./containers/FinancialTransactionDetail";
import Alerts from "./containers/Alerts";
import AlertDetail from "./containers/AlertDetail";
import Dashboard from "./containers/Dashboard";
import ReportStockIn from "./containers/reports/ReportStockIn";
import ReportStockOut from "./containers/reports/ReportStockOut";
import ReportStockOnHand from "./containers/reports/ReportStockOnHand";
import ReportRevenue from "./containers/reports/ReportRevenue";

const { Header, Sider, Content } = Layout;

function App() {
  const user = useRecoilValue(userState);
  const navigate = useNavigate();
  const location = useLocation();
  const {
    token: { colorBgContainer },
  } = theme.useToken();

  useEffect(() => {
    const token = localStorage.getItem("token");
    if (!token && location.pathname !== "/login") {
      navigate("/login");
    }
  }, [navigate, location]);

  if (!user && location.pathname !== "/login") {
    return (
      <Spin
        size="large"
        style={{ display: "flex", justifyContent: "center", alignItems: "center", height: "100vh" }}
      />
    );
  }

  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        element={
          <Layout style={{ minHeight: "100vh" }}>
            <Sider collapsible width={240} theme="dark">
              <Sidebar />
            </Sider>
            <Layout>
              <Header style={{ background: colorBgContainer, padding: 0, height: 64 }}>
                <Topbar />
              </Header>
              <Content style={{ margin: "16px" }}>
                <Outlet />
              </Content>
            </Layout>
          </Layout>
        }
      >
        <Route path="/" element={<Dashboard />} />
        <Route path="/products" element={<Products />} />
        <Route path="/categories" element={<Categories />} />
        <Route path="/units" element={<Units />} />
        <Route path="/suppliers" element={<Suppliers />} />
        <Route path="/customers" element={<Customers />} />
        <Route path="/promotions" element={<Promotions />} />
        <Route path="/orders" element={<Orders />} />
        <Route path="/ordersPOS" element={<OrderPOS />} />
        <Route path="/orders/:id" element={<OrderDetail />} />
        <Route path="/purchases" element={<Purchases />} />
        <Route path="/purchases/detail/:id" element={<PurchaseDetail />} />
        <Route path="/purchases/create" element={<PurchaseCreate />} />
        <Route path="/purchases/edit/:id" element={<PurchaseCreate />} />

        <Route path="/financial-transactions" element={<FinancialTransactions />} />
        <Route path="/financial-transactions/:id" element={<FinancialTransactionDetail />} />
        <Route path="/alerts" element={<Alerts />} />
        <Route path="/alerts/:id" element={<AlertDetail />} />

        <Route path="/reports/stock-in" element={<ReportStockIn />} />
        <Route path="/reports/stock-out" element={<ReportStockOut />} />
        <Route path="/reports/stock-on-hand" element={<ReportStockOnHand />} />
        <Route path="/reports/revenue" element={<ReportRevenue />} />

        <Route path="/settings" element={<Settings />} />
      </Route>
    </Routes>
  );
}

export default App;
