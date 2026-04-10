/** Matches backend: admin | client (legacy cashier/warehouse shown as client after login). */
export const ROLE_ADMIN = "admin";
export const ROLE_CLIENT = "client";

export function isAdmin(role) {
  return role === ROLE_ADMIN;
}

/** Menu / route access: admin sees everything; client sees operational areas. */
export function menuRolesForAdminAndClient() {
  return [ROLE_ADMIN, ROLE_CLIENT];
}
