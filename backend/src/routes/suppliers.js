// backend/src/routes/suppliers.js
const express = require('express');
const router = express.Router();
const pool = require('../db');
const auth = require('../middleware/auth');

// GET list suppliers
router.get('/', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;

    const { rows } = await pool.query(
      'SELECT supplier_id, name, phone, email FROM suppliers ORDER BY supplier_id LIMIT $1 OFFSET $2',
      [limit, offset]
    );
    const { rows: countRows } = await pool.query('SELECT COUNT(*) FROM suppliers');
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// GET supplier detail
router.get('/:id', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT s.*, p.name AS product_name, p.stock 
       FROM suppliers s 
       LEFT JOIN products p ON s.supplier_id = p.supplier_id 
       WHERE s.supplier_id = $1`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    const supplier = rows[0];
    supplier.products = rows.map(row => ({ product_name: row.product_name, stock: row.stock }));
    res.json({ success: true, data: supplier });
  } catch (err) {
    next(err);
  }
});

// POST create supplier
router.post('/', auth(['admin']), async (req, res, next) => {
  const { name, phone, email, address } = req.body;
  try {
    const { rows } = await pool.query(
      'INSERT INTO suppliers (name, phone, email, address) VALUES ($1, $2, $3, $4) RETURNING *',
      [name, phone, email, address]
    );
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// PUT update
router.put('/:id', auth(['admin']), async (req, res, next) => {
  const { name, phone, email, address } = req.body;
  try {
    const { rows } = await pool.query(
      'UPDATE suppliers SET name = $1, phone = $2, email = $3, address = $4 WHERE supplier_id = $5 RETURNING *',
      [name, phone, email, address, req.params.id]
    );
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// DELETE
router.delete('/:id', auth(['admin']), async (req, res, next) => {
  try {
    await pool.query('DELETE FROM suppliers WHERE supplier_id = $1', [req.params.id]);
    res.json({ success: true, message: 'Deleted' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;