// backend/src/routes/categories.js
const express = require('express');
const router = express.Router();
const pool = require('../db');
const auth = require('../middleware/auth');
const { query, validationResult } = require('express-validator');

// GET list categories (pagination)
router.get('/', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 999;
    const offset = (page - 1) * limit;

    const { rows } = await pool.query(
      'SELECT category_id, name, created_at FROM categories ORDER BY category_id LIMIT $1 OFFSET $2',
      [limit, offset]
    );
    const { rows: countRows } = await pool.query('SELECT COUNT(*) FROM categories');
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// GET category detail with join products
router.get('/:id', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT c.*, p.product_id, p.name AS product_name, p.barcode, p.stock 
       FROM categories c 
       LEFT JOIN products p ON c.category_id = p.category_id 
       WHERE c.category_id = $1`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    const category = rows[0];
    category.products = rows.map(row => ({ product_id: row.product_id, name: row.product_name, barcode: row.barcode, stock: row.stock }));
    res.json({ success: true, data: category });
  } catch (err) {
    next(err);
  }
});

// POST create category (admin only)
router.post('/', auth(['admin']), async (req, res, next) => {
  const { name, description } = req.body;
  try {
    const { rows } = await pool.query(
      'INSERT INTO categories (name, description) VALUES ($1, $2) RETURNING *',
      [name, description]
    );
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// PUT update category
router.put('/:id', auth(['admin']), async (req, res, next) => {
  const { name, description } = req.body;
  try {
    const { rows } = await pool.query(
      'UPDATE categories SET name = $1, description = $2 WHERE category_id = $3 RETURNING *',
      [name, description, req.params.id]
    );
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// DELETE category
router.delete('/:id', auth(['admin']), async (req, res, next) => {
  try {
    await pool.query('DELETE FROM categories WHERE category_id = $1', [req.params.id]);
    res.json({ success: true, message: 'Deleted' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;