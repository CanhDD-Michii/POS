import dayjs from "dayjs";

// export const fmtDateTime = (date) => {
//   if (!date) return "";
//   return dayjs(date).format("DD/MM/YYYY HH:mm");
// };

export const fmtDateForAPI = (date) => {
  if (!date) return null;
  return dayjs(date).format("YYYY-MM-DD");
};

// src/utils/date.js
export function pad(n) {
  return n < 10 ? `0${n}` : `${n}`;
}

export function toYMD(d) {
  if (!d) return "";
  const dt = new Date(d);
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}`;
}

export function fmtDateTime(d) {
  if (!d) return "—";
  const dt = new Date(d);
  if (Number.isNaN(dt.getTime())) return "—";
  return dt.toLocaleString("vi-VN");
}

export function currency(v) {
  const n = Number(v || 0);
  return n.toLocaleString("vi-VN") + " đ";
}

// Quick ranges (trả về [startYMD, endYMD])
export const quickRanges = {
  today() {
    const now = new Date();
    const s = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const e = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
    return [toYMD(s), toYMD(e)];
  },
  thisWeek() {
    const now = new Date();
    const day = now.getDay() || 7; // CN=7
    const s = new Date(now); s.setDate(now.getDate() - (day - 1)); s.setHours(0,0,0,0);
    const e = new Date(s); e.setDate(s.getDate() + 6); e.setHours(23,59,59,999);
    return [toYMD(s), toYMD(e)];
  },
  thisMonth() {
    const now = new Date();
    const s = new Date(now.getFullYear(), now.getMonth(), 1);
    const e = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23,59,59,999);
    return [toYMD(s), toYMD(e)];
  },
  thisYear() {
    const now = new Date();
    const s = new Date(now.getFullYear(), 0, 1);
    const e = new Date(now.getFullYear(), 11, 31, 23,59,59,999);
    return [toYMD(s), toYMD(e)];
  },
};
