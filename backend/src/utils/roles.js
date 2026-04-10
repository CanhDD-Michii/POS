/**
 * Application exposes two logical roles: admin and client.
 * Legacy DB values (cashier, warehouse) are normalized at login to "client".
 */

const ROLE_ADMIN = "admin";
const ROLE_CLIENT = "client";

/** DB roles that map to client-facing permissions */
const LEGACY_CLIENT_ROLES = new Set(["client", "cashier", "warehouse"]);

function normalizeRole(dbRole) {
  if (dbRole === ROLE_ADMIN) return ROLE_ADMIN;
  return ROLE_CLIENT;
}

/** True if JWT / DB role should be treated as client (non-admin). */
function isClientRole(role) {
  return role !== ROLE_ADMIN;
}

module.exports = {
  ROLE_ADMIN,
  ROLE_CLIENT,
  LEGACY_CLIENT_ROLES,
  normalizeRole,
  isClientRole,
};
