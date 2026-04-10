/**
 * API and static asset origins — override via Vite env in production.
 */
export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL ?? "http://localhost:3000/api";

export const UPLOADS_ORIGIN =
  import.meta.env.VITE_UPLOADS_ORIGIN ?? "http://localhost:3000";
