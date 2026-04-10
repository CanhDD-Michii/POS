const express = require('express');
const router = express.Router();
const pool = require('../db');
const auth = require('../middleware/auth');

// GET list
router.get('/', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;

    const { rows } = await pool.query(
      'SELECT payment_method_id, code, name, is_active FROM payment_methods ORDER BY payment_method_id LIMIT $1 OFFSET $2',
      [limit, offset]
    );
    const { rows: countRows } = await pool.query('SELECT COUNT(*) FROM payment_methods');
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// GET detail
router.get('/:id', async (req, res, next) => {
  try {
    const { rows: usage } = await pool.query(
      `SELECT COUNT(o.order_id) AS orders_count, COUNT(pur.purchase_id) AS purchases_count 
       FROM payment_methods pm 
       LEFT JOIN orders o ON pm.payment_method_id = o.payment_method_id 
       LEFT JOIN purchases pur ON pm.payment_method_id = pur.payment_method_id 
       WHERE pm.payment_method_id = $1 
       GROUP BY pm.payment_method_id`,
      [req.params.id]
    );
    const { rows } = await pool.query('SELECT * FROM payment_methods WHERE payment_method_id = $1', [req.params.id]);
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    rows[0].usage = usage[0] || { orders_count: 0, purchases_count: 0 };
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// POST create
router.post('/', auth(['admin']), async (req, res, next) => {
  const { code, name, description } = req.body;
  try {
    const { rows } = await pool.query(
      'INSERT INTO payment_methods (code, name, description) VALUES ($1, $2, $3) RETURNING *',
      [code, name, description]
    );
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// Toggle active
router.put('/:id/toggle', auth(['admin']), async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      'UPDATE payment_methods SET is_active = NOT is_active WHERE payment_method_id = $1 RETURNING *',
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// DELETE
router.delete('/:id', auth(['admin']), async (req, res, next) => {
  try {
    const { rows } = await pool.query('DELETE FROM payment_methods WHERE payment_method_id = $1 RETURNING *', [req.params.id]);
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, message: 'Deleted' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;