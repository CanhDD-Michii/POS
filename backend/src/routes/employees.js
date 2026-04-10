const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");
const bcrypt = require("bcrypt");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const { normalizeRole } = require("../utils/roles");

const uploadDir = path.join(__dirname, "..", "..", "uploads", "avatars");
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || "") || ".jpg";
    cb(null, `emp-${req.user.id}-${Date.now()}${ext}`);
  },
});
const upload = multer({ storage, limits: { fileSize: 3 * 1024 * 1024 } });

/**
 * Update current user profile (name, optional avatar file).
 */
router.put("/me", auth(), upload.single("avatar"), async (req, res, next) => {
  try {
    const userId = req.user.id;
    const name = req.body.name;

    const fields = [];
    const values = [];
    let idx = 1;

    if (name != null && String(name).trim()) {
      fields.push(`name = $${idx++}`);
      values.push(String(name).trim());
    }
    if (req.file) {
      const publicPath = `/uploads/avatars/${req.file.filename}`;
      fields.push(`avatar = $${idx++}`);
      values.push(publicPath);
    }

    if (!fields.length) {
      return res.status(400).json({ success: false, error: "No fields to update" });
    }

    values.push(userId);
    const q = `UPDATE employees SET ${fields.join(", ")} WHERE employee_id = $${idx} RETURNING employee_id, username, role, avatar, name`;
    const { rows } = await pool.query(q, values);
    if (!rows.length) return res.status(404).json({ success: false, error: "Not found" });

    const row = rows[0];
    res.json({
      success: true,
      data: {
        id: row.employee_id,
        username: row.username,
        role: normalizeRole(row.role),
        avatar: row.avatar,
        name: row.name,
      },
    });
  } catch (err) {
    next(err);
  }
});

/**
 * Change password for the authenticated user.
 */
router.put("/change-password", auth(), async (req, res, next) => {
  try {
    const userId = req.user.id;
    const { oldPassword, newPassword } = req.body;
    if (!oldPassword || !newPassword) {
      return res.status(400).json({ success: false, error: "Missing passwords" });
    }

    const { rows } = await pool.query(
      "SELECT password_hash FROM employees WHERE employee_id = $1",
      [userId]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: "Not found" });

    const hash = rows[0].password_hash;
    const ok =
      hash?.startsWith("$2b$")
        ? await bcrypt.compare(oldPassword, hash)
        : oldPassword === hash;
    if (!ok) {
      return res.status(401).json({ success: false, error: "Wrong current password" });
    }

    const newHash = await bcrypt.hash(newPassword, 10);
    await pool.query("UPDATE employees SET password_hash = $1 WHERE employee_id = $2", [
      newHash,
      userId,
    ]);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
