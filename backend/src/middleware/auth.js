// backend/src/middleware/auth.js
const jwt = require("jsonwebtoken");
const { ROLE_CLIENT, LEGACY_CLIENT_ROLES } = require("../utils/roles");

/**
 * Expand route requirement "client" to include legacy JWT roles still in circulation.
 */
function roleMatchesRoute(decodedRole, allowedRoles) {
  if (!allowedRoles.length) return true;
  for (const r of allowedRoles) {
    if (r === ROLE_CLIENT && LEGACY_CLIENT_ROLES.has(decodedRole)) return true;
    if (r === decodedRole) return true;
  }
  return false;
}

const auth = (roles) => {
  if (!roles) roles = [];
  if (typeof roles === "string") roles = [roles];

  return (req, res, next) => {
    const token = req.headers.authorization?.split(" ")[1];
    if (!token)
      return res.status(401).json({ success: false, error: "No token" });

    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET);

      if (roles.length && !roleMatchesRoute(decoded.role, roles)) {
        return res
          .status(403)
          .json({ success: false, error: "Forbidden (insufficient role)" });
      }

      req.user = decoded;
      next();
    } catch (err) {
      res.status(401).json({ success: false, error: "Invalid token" });
    }
  };
};

module.exports = auth;