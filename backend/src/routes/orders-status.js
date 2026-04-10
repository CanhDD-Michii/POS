const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");

// UPDATE trạng thái hóa đơn
router.put("/orders/:orderNumber/status", auth(["admin", "client"]), async (req, res) => {
  try {
    const { status } = req.body;
    await pool.query(
      `UPDATE orders SET status=$1, updated_at=NOW() WHERE order_number=$2`,
      [status, req.params.orderNumber]
    );
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false });
  }
});

module.exports = router;
