// backend/src/routes/promotions.js
const express = require('express');
const router = express.Router();
const pool = require('../db');
const auth = require('../middleware/auth');

// GET list promotions
router.get('/', async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;

    const { rows } = await pool.query(
      'SELECT promotion_id, name, discount_percent, start_date, end_date FROM promotions ORDER BY promotion_id LIMIT $1 OFFSET $2',
      [limit, offset]
    );
    const { rows: countRows } = await pool.query('SELECT COUNT(*) FROM promotions');
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// GET promotion detail
router.get('/:id', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT p.*, c.name AS category_name, pr.name AS product_name, o.order_number
       FROM promotions p 
       LEFT JOIN promotion_categories pc ON p.promotion_id = pc.promotion_id
       LEFT JOIN categories c ON pc.category_id = c.category_id
       LEFT JOIN promotion_products pp ON p.promotion_id = pp.promotion_id
       LEFT JOIN products pr ON pp.product_id = pr.product_id
       LEFT JOIN orders o ON p.promotion_id = o.promotion_id
       WHERE p.promotion_id = $1`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    const promotion = rows[0];
    promotion.categories = rows.map(row => row.category_name).filter(Boolean);
    promotion.products = rows.map(row => row.product_name).filter(Boolean);
    promotion.orders = rows.map(row => row.order_number).filter(Boolean);
    res.json({ success: true, data: promotion });
  } catch (err) {
    next(err);
  }
});

// POST create promotion
router.post('/', auth(['admin']), async (req, res, next) => {
  const { name, discount_percent, start_date, end_date } = req.body;
  try {
    const { rows } = await pool.query(
      'INSERT INTO promotions (name, discount_percent, start_date, end_date) VALUES ($1, $2, $3, $4) RETURNING *',
      [name, discount_percent, start_date, end_date]
    );
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// Apply categories to promotion
router.post('/:id/apply-categories', auth(['admin']), async (req, res, next) => {
  const { category_ids } = req.body;
  try {
    const values = category_ids.map(id => `(${req.params.id}, ${id})`).join(',');
    await pool.query(`INSERT INTO promotion_categories (promotion_id, category_id) VALUES ${values} ON CONFLICT DO NOTHING`);
    res.json({ success: true, message: 'Applied' });
  } catch (err) {
    next(err);
  }
});

// Apply products to promotion
router.post('/:id/apply-products', auth(['admin']), async (req, res, next) => {
  const { product_ids } = req.body;
  try {
    const values = product_ids.map(id => `(${req.params.id}, ${id})`).join(',');
    await pool.query(`INSERT INTO promotion_products (promotion_id, product_id) VALUES ${values} ON CONFLICT DO NOTHING`);
    res.json({ success: true, message: 'Applied' });
  } catch (err) {
    next(err);
  }
});

// PUT update promotion
router.put('/:id', auth(['admin']), async (req, res, next) => {
  const { name, discount_percent, start_date, end_date } = req.body;
  try {
    const { rows } = await pool.query(
      `UPDATE promotions
       SET name = $1, discount_percent = $2, start_date = $3, end_date = $4
       WHERE promotion_id = $5 RETURNING *`,
      [name, discount_percent, start_date, end_date, req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// DELETE promotion
router.delete('/:id', auth(['admin']), async (req, res, next) => {
  try {
    const { rowCount } = await pool.query(
      'DELETE FROM promotions WHERE promotion_id = $1',
      [req.params.id]
    );
    if (!rowCount) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, message: 'Deleted' });
  } catch (err) {
    next(err);
  }
});


module.exports = router;