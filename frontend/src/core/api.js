import axios from "axios";
import { API_BASE_URL } from "../config/constants";

const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    "Content-Type": "application/json",
  },
});

apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem("token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

/**
 * Login hits root server path /api/login (same origin pattern as other /api routes).
 */
export const login = async (username, password) => {
  const base = API_BASE_URL.replace(/\/api\/?$/, "");
  const response = await axios.post(`${base}/api/login`, { username, password });
  return response.data;
};

export const checkAuth = async () => {
  const base = API_BASE_URL.replace(/\/api\/?$/, "");
  const token = localStorage.getItem("token");
  const response = await axios.get(`${base}/check`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return response.data;
};

export default apiClient;
