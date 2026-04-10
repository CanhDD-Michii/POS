const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");

// ========== Lấy danh sách ==========
// ========== Lấy danh sách với filter ==========
router.get("/", async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;

    // Lấy params filter
    const { type, status, search, start_date, end_date } = req.query;

    // Build WHERE clause
    let where = [];
    let params = [];
    let paramIndex = 1;

    if (type) {
      where.push(`ft.type = $${paramIndex++}`);
      params.push(type);
    }
    if (status) {
      where.push(`ft.status = $${paramIndex++}`);
      params.push(status);
    }
    if (search) {
      where.push(`
        (ft.original_document_number ILIKE $${paramIndex}
         OR ft.payer_receiver_name ILIKE $${paramIndex}
         OR pm.name ILIKE $${paramIndex}
         OR CAST(ft.transaction_id AS TEXT) ILIKE $${paramIndex})
      `);
      params.push(`%${search}%`);
    }
    if (start_date) {
      where.push(`ft.transaction_date >= $${paramIndex++}`);
      params.push(start_date);
    }
    if (end_date) {
      where.push(
        `ft.transaction_date < ($${paramIndex++}::date + INTERVAL '1 day')`
      );
      params.push(end_date);
    }

    const whereClause = where.length ? "WHERE " + where.join(" AND ") : "";

    // Query data
    const { rows } = await pool.query(
      `SELECT 
         ft.transaction_id,
         ft.type,
         ft.amount,
         ft.transaction_date,
         ft.status,
         ft.original_document_number,
         ft.payer_receiver_name,
         ft.original_document_number AS "or",
         pm.name AS payment_method_name,
         e.name AS employee_name
       FROM financial_transactions ft
       LEFT JOIN payment_methods pm ON ft.payment_method_id = pm.payment_method_id
       LEFT JOIN employees e ON ft.employee_id = e.employee_id
       ${whereClause}
       ORDER BY ft.transaction_id DESC
       LIMIT $${paramIndex++} OFFSET $${paramIndex++}`,
      [...params, limit, offset]
    );

    // Query total (với cùng filter)
    const countQuery = `
      SELECT COUNT(*) 
      FROM financial_transactions ft
      LEFT JOIN payment_methods pm ON ft.payment_method_id = pm.payment_method_id
      ${whereClause.replace(
        /ft\.original_document_number ILIKE \$\$(\d+)/g,
        (_, i) =>
          `(ft.original_document_number ILIKE $${i} OR ft.payer_receiver_name ILIKE $${i} OR pm.name ILIKE $${i} OR CAST(ft.transaction_id AS TEXT) ILIKE $${i})`
      )}
    `;
    const { rows: countRows } = await pool.query(countQuery, params);
    const total = parseInt(countRows[0].count);

    res.json({
      success: true,
      data: rows,
      pagination: { page, limit, total },
    });
  } catch (err) {
    console.error("Error in financial-transactions GET /:", err);
    next(err);
  }
});

// ========== Xem chi tiết ==========
router.get("/:id", async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT 
         ft.*, 
         e.name AS employee_name,
         pm.name AS payment_method_name,
         c.name AS customer_name,
         s.name AS supplier_name
       FROM financial_transactions ft
       LEFT JOIN employees e ON ft.employee_id = e.employee_id
       LEFT JOIN payment_methods pm ON ft.payment_method_id = pm.payment_method_id
       LEFT JOIN customers c ON ft.customer_id = c.customer_id
       LEFT JOIN suppliers s ON ft.supplier_id = s.supplier_id
       WHERE ft.transaction_id = $1`,
      [req.params.id]
    );

    if (!rows.length)
      return res.status(404).json({ success: false, error: "Not found" });

    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// ========== Thêm giao dịch ==========
router.post(
  "/",
  auth(["admin", "client"]),
  async (req, res, next) => {
    try {
      const {
        type,
        note,
        amount,
        transaction_date,
        original_document_number,
        customer_id,
        supplier_id,
        payer_receiver_name,
        payer_receiver_phone,
        payer_receiver_address,
        related_order_id,
        related_purchase_id,
        payment_method_id,
        status,
      } = req.body;

      const employee_id = req.user?.id;
      if (!employee_id)
        return res
          .status(401)
          .json({ success: false, error: "Thiếu thông tin nhân viên (token)" });

      const { rows } = await pool.query(
        `INSERT INTO financial_transactions
       (type, note, amount, transaction_date, employee_id, original_document_number,
        customer_id, supplier_id, payer_receiver_name, payer_receiver_phone,
        payer_receiver_address, related_order_id, related_purchase_id,
        payment_method_id, status, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,NOW())
       RETURNING *`,
        [
          type,
          note,
          amount,
          transaction_date,
          employee_id,
          original_document_number,
          customer_id,
          supplier_id,
          payer_receiver_name,
          payer_receiver_phone,
          payer_receiver_address,
          related_order_id,
          related_purchase_id,
          payment_method_id,
          status,
        ]
      );

      res.status(201).json({ success: true, data: rows[0] });
    } catch (err) {
      next(err);
    }
  }
);

// ========== Sửa ==========
router.put("/:id", auth(["admin", "client"]), async (req, res, next) => {
  try {
    const fields = [];
    const values = [];
    let index = 1;

    for (const key of [
      "type",
      "note",
      "amount",
      "transaction_date",
      "original_document_number",
      "customer_id",
      "supplier_id",
      "payer_receiver_name",
      "payer_receiver_phone",
      "payer_receiver_address",
      "related_order_id",
      "related_purchase_id",
      "payment_method_id",
      "status",
    ]) {
      if (req.body[key] !== undefined) {
        fields.push(`${key} = $${index++}`);
        values.push(req.body[key]);
      }
    }

    if (!fields.length)
      return res
        .status(400)
        .json({ success: false, error: "Không có dữ liệu để cập nhật" });

    values.push(req.params.id);

    const { rows } = await pool.query(
      `UPDATE financial_transactions SET ${fields.join(
        ", "
      )} WHERE transaction_id = $${index} RETURNING *`,
      values
    );

    if (!rows.length)
      return res.status(404).json({ success: false, error: "Không tìm thấy" });

    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// ========== Xóa ==========
router.delete("/:id", auth(["admin"]), async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      "DELETE FROM financial_transactions WHERE transaction_id = $1 RETURNING *",
      [req.params.id]
    );
    if (!rows.length)
      return res.status(404).json({ success: false, error: "Không tìm thấy" });

    res.json({ success: true, message: "Đã xóa giao dịch" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
