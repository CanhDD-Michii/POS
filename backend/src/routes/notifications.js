// backend/src/routes/notifications.js
const express = require('express');
const router = express.Router();
const pool = require('../db');
const auth = require('../middleware/auth');

// Get alerts for notification
router.get('/alerts', auth(), async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT a.message, a.severity, p.name AS product_name 
       FROM alerts a 
       LEFT JOIN products p ON a.related_product_id = p.product_id 
       WHERE a.is_resolved = FALSE 
       ORDER BY a.created_at DESC LIMIT 5`
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
});

module.exports = router;