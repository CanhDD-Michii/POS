// frontend/src/router/index.jsx
import { Routes, Route, Navigate } from 'react-router-dom';
import { useRecoilValue } from 'recoil';
import { userState } from '../core/atoms';
import Login from '../containers/Login';
import Dashboard from '../containers/Dashboard';
import Products from '../containers/Products';
import Orders from '../containers/Orders';

const ProtectedRoute = ({ children }) => {
  const user = useRecoilValue(userState);
  const token = localStorage.getItem('token');
  console.log('ProtectedRoute: user =', user, 'token =', token);

  // Nếu không có user và không có token => quay lại login
  if (!user && !token) {
    return <Navigate to="/login" replace />;
  }

  return children;
};


const AppRoutes = () => {
  console.log('AppRoutes: Render routes'); // Debug: Xác nhận routes render
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <Dashboard />
          </ProtectedRoute>
        }
      />
      <Route
        path="/products"
        element={
          <ProtectedRoute>
            <Products />
          </ProtectedRoute>
        }
      />
      <Route
        path="/orders"
        element={
          <ProtectedRoute>
            <Orders />
          </ProtectedRoute>
        }
      />
      <Route path="/" element={<Navigate to="/login" replace />} />
    </Routes>
  );
};

export default AppRoutes;