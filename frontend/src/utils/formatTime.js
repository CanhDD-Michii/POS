// src/utils/formatTime.js
import moment from 'moment';

export function relativeTime(input) {
  if (!input) return "—";
  const t = new Date(input);
  if (isNaN(t.getTime())) return "—";
  const now = new Date();
  const diff = Math.floor((now.getTime() - t.getTime()) / 1000); // seconds

  if (diff < 5) return "vừa xong";
  if (diff < 60) return `${diff}s trước`;
  const m = Math.floor(diff / 60);
  if (m < 60) return `${m} phút trước`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h} giờ trước`;
  const d = Math.floor(h / 24);
  if (d === 1) return "Hôm qua";
  if (d < 7) return `${d} ngày trước`;
  const w = Math.floor(d / 7);
  if (w < 5) return `${w} tuần trước`;
  const mo = Math.floor(d / 30);
  if (mo < 12) return `${mo} tháng trước`;
  const y = Math.floor(d / 365);
  return `${y} năm trước`;
}

// Format ngày giờ đầy đủ
export function formatDateTime(input) {
  if (!input) return "—";
  const t = new Date(input);
  if (isNaN(t.getTime())) return "—";
  return moment(t).format("DD/MM/YYYY HH:mm");
}

// Format ngày giờ với relative time kèm theo
export function formatDateTimeWithRelative(input) {
  if (!input) return "—";
  const t = new Date(input);
  if (isNaN(t.getTime())) return "—";
  const dateTime = moment(t).format("DD/MM/YYYY HH:mm");
  const relative = relativeTime(input);
  return `${dateTime} (${relative})`;
}

export const severityMeta = {
  low:   { color: "green",  icon: "info" },
  medium:{ color: "gold",   icon: "warn" },
  high:  { color: "red",    icon: "error" },
};
