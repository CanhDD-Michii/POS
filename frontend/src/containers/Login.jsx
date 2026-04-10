import { Form, Input, Button, message } from "antd";
import { UserOutlined, LockOutlined } from "@ant-design/icons";
import { useRecoilState } from "recoil";
import { userState } from "../core/atoms";
import { login } from "../core/api";
import { useNavigate } from "react-router-dom";
// import styles from "../styles/Login.module.css"; // Import CSS

function Login() {
  const [user, setUser] = useRecoilState(userState); // eslint-disable-line no-unused-vars
  const navigate = useNavigate();

  const onFinish = async (values) => {
    try {
      const { success, token, data } = await login(
        values.username,
        values.password
      );
      if (success) {
        setUser({
          id: data.id,
          username: data.username,
          role: data.role,
          avatar: data.avatar,
          token,
        });
        localStorage.setItem("token", token);
        localStorage.setItem(
          "user",
          JSON.stringify({
            id: data.id,
            username: data.username,
            role: data.role,
            avatar: data.avatar,
          })
        );
        navigate("/");
        message.success("Đăng nhập thành công");
      } else {
        message.error("Sai tên đăng nhập hoặc mật khẩu");
      }
    } catch (err) {
      // Xử lý lỗi từ backend
      const errorMessage = err?.response?.data?.error || err?.message;
      if (err?.response?.status === 401) {
        // Lỗi xác thực - hiển thị message từ backend (đã là tiếng Việt)
        message.error(errorMessage || "Sai tên đăng nhập hoặc mật khẩu");
      } else if (err?.response?.status === 400) {
        // Lỗi thiếu thông tin
        message.error(errorMessage || "Vui lòng nhập đầy đủ thông tin!");
      } else if (err?.response?.status === 500) {
        // Lỗi server
        message.error(errorMessage || "Lỗi hệ thống! Vui lòng thử lại sau.");
      } else if (!err.response) {
        // Lỗi kết nối (không có response từ server)
        message.error("Không thể kết nối đến server!");
      } else {
        // Lỗi khác
        message.error(errorMessage || "Đăng nhập thất bại!");
      }
      console.error("Login error:", err);
    }
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        backgroundColor: "#667eea",
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        fontFamily: "Segoe UI, Tahoma, sans-serif",
        position: "relative",
      }}
    >
      {/* NỀN ICON THÚ Y MỜ */}


      {/* CARD */}
      <div
        style={{
          width: 360,
          background: "#fff",
          borderRadius: 10,
          border: "1px solid #e5e7eb",
          boxShadow: "0 6px 18px rgba(0,0,0,0.06)",
          position: "relative",
          zIndex: 1,
          overflow: "hidden",
        }}
      >
        {/* WATERMARK ICON */}
        <div
          style={{
            position: "absolute",
            bottom: -20,
            right: -10,
            fontSize: 120,
            opacity: 0.05,
            pointerEvents: "none",
          }}
        >
          🐾
        </div>

        {/* HEADER */}
        <div
          style={{
            padding: "22px 20px",
            textAlign: "center",
            borderBottom: "1px solid #f0f0f0",
          }}
        >
          <div
            style={{
              width: 56,
              height: 56,
              margin: "0 auto 10px",
              background: "#e6f4ea",
              color: "#2f855a",
              borderRadius: "50%",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 28,
            }}
          >
            🐶
          </div>

          <h2 style={{ margin: 0, fontSize: 20, color: "#2d3748" }}>
            Quản lý văn phòng phẩm Ngọc Dương
          </h2>
          <p style={{ marginTop: 6, fontSize: 13, color: "#718096" }}>
            Đăng nhập để tiếp tục quản lý cửa hàng
          </p>
        </div>

        {/* FORM */}
        <div style={{ padding: "22px 24px 26px" }}>
          <Form name="login" onFinish={onFinish} layout="vertical">
            <Form.Item
              name="username"
              rules={[
                { required: true, message: "Vui lòng nhập tên đăng nhập!" },
              ]}
            >
              <Input
                prefix={<UserOutlined />}
                placeholder="Tên đăng nhập"
                size="large"
                style={{ borderRadius: 6, height: 42 }}
              />
            </Form.Item>

            <Form.Item
              name="password"
              rules={[{ required: true, message: "Vui lòng nhập mật khẩu!" }]}
            >
              <Input.Password
                prefix={<LockOutlined />}
                placeholder="Mật khẩu"
                size="large"
                style={{ borderRadius: 6, height: 42 }}
              />
            </Form.Item>

            <Form.Item style={{ marginBottom: 0 }}>
              <Button
                htmlType="submit"
                size="large"
                style={{
                  width: "100%",
                  height: 42,
                  borderRadius: 6,
                  background: "#38a169",
                  border: "none",
                  fontWeight: 600,
                  color: "#fff",
                }}
              >
                Đăng nhập
              </Button>
            </Form.Item>
          </Form>

          <div
            style={{
              textAlign: "center",
              marginTop: 18,
              fontSize: 12,
              color: "#a0aec0",
            }}
          >
            © 2025 Hệ thống quản lý văn phòng phẩm Ngọc Dương
          </div>
        </div>
      </div>
    </div>
  );
}

export default Login;
