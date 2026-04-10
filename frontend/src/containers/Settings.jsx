// frontend/src/containers/Settings.jsx (Trang Cài đặt mới, với form chỉnh avatar, đổi mật khẩu, thông tin cá nhân)
import { Form, Input, Button, Upload, message, Avatar, Switch, Select } from 'antd';
import { UploadOutlined, UserOutlined } from '@ant-design/icons';
import { useRecoilState } from 'recoil';
import { userState } from '../core/atoms';
import apiClient from '../core/api';
import { useNavigate } from 'react-router-dom';
import { useState, useEffect } from 'react';

function Settings() {
  const [user, setUser] = useRecoilState(userState);
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);
  const [darkMode, setDarkMode] = useState(false); // Trạng thái theme tối (thêm gợi ý)
  // eslint-disable-next-line no-unused-vars
  const navigate = useNavigate();

  useEffect(() => {
    form.setFieldsValue({
      name: user?.name,
      username: user?.username,
      email: user?.email, // Giả định có email trong user
      role: user?.role,
      avatar: user?.avatar,
    });
  }, [user, form]);

  const handleUpdateProfile = async (values) => {
    setLoading(true);
    try {
      const formData = new FormData();
      formData.append('name', values.name);
      formData.append('email', values.email);
      if (values.avatar?.file) {
        formData.append('avatar', values.avatar.file.originFileObj);
      }
      const response = await apiClient.put('/employees/me', formData, { headers: { 'Content-Type': 'multipart/form-data' } });
      const payload = response.data?.data;
      if (payload) {
        setUser({
          ...user,
          id: payload.id,
          username: payload.username,
          role: payload.role,
          avatar: payload.avatar,
          name: payload.name,
        });
      }
      message.success('Cập nhật thông tin thành công');
    } catch (err) {
      message.error('Cập nhật thất bại');
      console.error(err);
    }
    setLoading(false);
  };

  const handleChangePassword = async (values) => {
    if (values.newPassword !== values.confirmPassword) {
      return message.error('Mật khẩu xác nhận không khớp');
    }
    setLoading(true);
    try {
      await apiClient.put('/employees/change-password', { oldPassword: values.oldPassword, newPassword: values.newPassword });
      message.success('Đổi mật khẩu thành công');
    } catch (err) {
      message.error('Đổi mật khẩu thất bại');
      console.error(err);
    }
    setLoading(false);
  };

  const handleForgotPassword = async (values) => {
    setLoading(true);
    try {
      await apiClient.post('/auth/forgot-password', { email: values.email });
      message.success('Yêu cầu lấy lại mật khẩu đã gửi');
    } catch (err) {
      message.error('Gửi yêu cầu thất bại');
      console.error(err);
    }
    setLoading(false);
  };

  const toggleDarkMode = () => {
    setDarkMode(!darkMode);
    // Lưu vào localStorage để giữ khi refresh
    localStorage.setItem('darkMode', !darkMode);
  };

  return (
    <div>
      <h2>Cài đặt</h2>
      <Form form={form} onFinish={handleUpdateProfile} layout="vertical">
        <Form.Item label="Avatar" name="avatar" valuePropName="file">
          <Upload name="avatar" listType="picture" maxCount={1}>
            <Button icon={<UploadOutlined />}>Upload avatar</Button>
          </Upload>
          <Avatar src={user?.avatar} icon={<UserOutlined />} size={64} />
        </Form.Item>
        <Form.Item label="Tên" name="name">
          <Input />
        </Form.Item>
        <Form.Item label="Email" name="email">
          <Input />
        </Form.Item>
        <Form.Item label="Vai trò" name="role">
          <Select disabled>
            <Select.Option value="admin">Admin</Select.Option>
            <Select.Option value="client">Client</Select.Option>
          </Select>
        </Form.Item>
        <Button type="primary" htmlType="submit" loading={loading}>Cập nhật thông tin</Button>
      </Form>

      <h3 style={{ marginTop: 24 }}>Đổi mật khẩu</h3>
      <Form onFinish={handleChangePassword} layout="vertical">
        <Form.Item label="Mật khẩu cũ" name="oldPassword" rules={[{ required: true }]}>
          <Input.Password />
        </Form.Item>
        <Form.Item label="Mật khẩu mới" name="newPassword" rules={[{ required: true }]}>
          <Input.Password />
        </Form.Item>
        <Form.Item label="Xác nhận mật khẩu" name="confirmPassword" rules={[{ required: true }]}>
          <Input.Password />
        </Form.Item>
        <Button type="primary" htmlType="submit" loading={loading}>Đổi mật khẩu</Button>
      </Form>

      <h3 style={{ marginTop: 24 }}>Lấy lại mật khẩu</h3>
      <Form onFinish={handleForgotPassword} layout="vertical">
        <Form.Item label="Email" name="email" rules={[{ required: true, type: 'email' }]}>
          <Input />
        </Form.Item>
        <Button type="primary" htmlType="submit" loading={loading}>Gửi yêu cầu</Button>
      </Form>

      <h3 style={{ marginTop: 24 }}>Chế độ tối</h3>
      <Switch checked={darkMode} onChange={toggleDarkMode} />
      {/* Thêm các chức năng khác nếu cần, ví dụ: Xem lịch sử hoạt động */}
    </div>
  );
}

export default Settings;