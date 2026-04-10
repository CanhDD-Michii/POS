// backend/src/routes/units.js
const express = require('express');
const router = express.Router();
const pool = require('../db');
const auth = require('../middleware/auth');

// GET list units
router.get('/', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;

    const { rows } = await pool.query(
      'SELECT unit_id, name, description FROM units ORDER BY unit_id LIMIT $1 OFFSET $2',
      [limit, offset]
    );
    const { rows: countRows } = await pool.query('SELECT COUNT(*) FROM units');
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// GET unit detail
router.get('/:id', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT u.*, p.product_id, p.name AS product_name, p.price
       FROM units u 
       LEFT JOIN products p ON u.unit_id = p.unit_id 
       WHERE u.unit_id = $1`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    const unit = rows[0];
    unit.products = rows.map(row => ({ product_id: row.product_id, name: row.product_name, price: row.price }));
    res.json({ success: true, data: unit });
  } catch (err) {
    next(err);
  }
});

// POST create unit
router.post('/', auth(['admin', 'client']), async (req, res, next) => {
  const { name, description } = req.body;
  try {
    const { rows } = await pool.query(
      'INSERT INTO units (name, description, created_at) VALUES ($1, $2, CURRENT_TIMESTAMP) RETURNING *',
      [name, description]
    );
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// PUT update unit
router.put('/:id', auth(['admin']), async (req, res, next) => {
  const { name, description } = req.body;
  try {
    const { rows } = await pool.query(
      'UPDATE units SET name = $1, description = $2 WHERE unit_id = $3 RETURNING *',
      [name, description, req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// DELETE unit
router.delete('/:id', auth(['admin']), async (req, res, next) => {
  try {
    const { rows } = await pool.query('DELETE FROM units WHERE unit_id = $1 RETURNING *', [req.params.id]);
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, message: 'Deleted' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;