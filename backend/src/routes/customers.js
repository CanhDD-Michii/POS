// backend/src/routes/customers.js
const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");

// GET list customers (bỏ points)
router.get("/", async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;

    const { rows } = await pool.query(
      "SELECT customer_id, name, phone FROM customers ORDER BY customer_id LIMIT $1 OFFSET $2",
      [limit, offset]
    );
    const { rows: countRows } = await pool.query("SELECT COUNT(*) FROM customers");
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// GET chi tiết customer (bỏ points)
router.get("/:id", async (req, res, next) => {
  try {
    const customerId = req.params.id;

    const { rows: customerRows } = await pool.query(
      `SELECT customer_id, name, phone, email, gender, birthday, address, created_at 
       FROM customers 
       WHERE customer_id = $1`,
      [customerId]
    );

    if (!customerRows.length) {
      return res.status(404).json({ success: false, message: "Customer not found" });
    }

    const customer = customerRows[0];

    // Lấy danh sách đơn hàng (nếu cần)
    const { rows: orderRows } = await pool.query(
      `SELECT order_id, order_number, order_date, total_amount, status 
       FROM orders 
       WHERE customer_id = $1 
       ORDER BY order_date DESC`,
      [customerId]
    );

    res.json({
      success: true,
      data: {
        ...customer,
        orders: orderRows
      }
    });
  } catch (err) {
    next(err);
  }
});

// POST tạo customer mới (bỏ points)
router.post("/", auth(["admin", "client"]), async (req, res, next) => {
  const { name, phone, email, gender, birthday, address } = req.body;
  try {
    const { rows } = await pool.query(
      `INSERT INTO customers 
       (name, phone, email, gender, birthday, address) 
       VALUES ($1, $2, $3, $4, $5, $6) 
       RETURNING customer_id, name, phone, email, gender, birthday, address, created_at`,
      [name, phone, email, gender, birthday || null, address || null]
    );
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// PUT cập nhật (bỏ points)
router.put("/:id", auth(["admin", "client"]), async (req, res, next) => {
  const { name, phone, email, gender, birthday, address } = req.body;
  try {
    const { rows } = await pool.query(
      `UPDATE customers 
       SET name = $1, phone = $2, email = $3, gender = $4, birthday = $5, address = $6
       WHERE customer_id = $7 
       RETURNING customer_id, name, phone, email, gender, birthday, address, created_at`,
      [name, phone, email, gender, birthday || null, address || null, req.params.id]
    );

    if (!rows.length) {
      return res.status(404).json({ success: false, message: "Customer not found" });
    }

    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// DELETE
router.delete("/:id", auth(["admin"]), async (req, res, next) => {
  try {
    const { rowCount } = await pool.query("DELETE FROM customers WHERE customer_id = $1", [req.params.id]);
    if (rowCount === 0) {
      return res.status(404).json({ success: false, message: "Customer not found" });
    }
    res.json({ success: true, message: "Customer deleted" });
  } catch (err) {
    next(err);
  }
});

module.exports = router;