// backend/src/routes/alerts.js
const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");

// Helper function: Cập nhật message cảnh báo tồn kho với số lượng stock mới nhất
// Trigger đã tự động tạo cảnh báo, hàm này chỉ cập nhật message với số lượng mới
// dbClient có thể là pool hoặc client từ transaction
async function checkAndCreateStockAlert(dbClient, productId) {
  try {
    // Lấy thông tin sản phẩm với stock mới nhất
    const { rows: products } = await dbClient.query(
      "SELECT product_id, name, stock, minimum_inventory, maximum_inventory FROM products WHERE product_id = $1",
      [productId]
    );

    if (!products.length) return;

    const p = products[0];

    // Kiểm tra low stock - cập nhật message của cảnh báo hiện có
    if (p.minimum_inventory !== null && p.stock < p.minimum_inventory) {
      const type = "low_stock";
      const message = `Sản phẩm "${p.name}" sắp hết hàng (còn ${p.stock}, dưới ngưỡng ${p.minimum_inventory})`;

      // Cập nhật message của cảnh báo hiện có (trigger đã tạo rồi)
      await dbClient.query(
        `UPDATE alerts 
         SET message = $1, updated_at = CURRENT_TIMESTAMP
         WHERE type = $2 AND related_product_id = $3 AND is_resolved = FALSE`,
        [message, type, productId]
      );
    }

    // Kiểm tra over stock - cập nhật message của cảnh báo hiện có
    if (p.maximum_inventory !== null && p.stock > p.maximum_inventory) {
      const type = "over_stock";
      const message = `Sản phẩm "${p.name}" vượt tồn kho tối đa (còn ${p.stock}, trên ngưỡng ${p.maximum_inventory})`;

      // Cập nhật message của cảnh báo hiện có (trigger đã tạo rồi)
      await dbClient.query(
        `UPDATE alerts 
         SET message = $1, updated_at = CURRENT_TIMESTAMP
         WHERE type = $2 AND related_product_id = $3 AND is_resolved = FALSE`,
        [message, type, productId]
      );
    }

    // Nếu stock trong khoảng bình thường, xóa cảnh báo cũ (nếu có)
    // if (
    //   (p.minimum_inventory === null || p.stock >= p.minimum_inventory) &&
    //   (p.maximum_inventory === null || p.stock <= p.maximum_inventory)
    // ) {
    //   await dbClient.query(
    //     'DELETE FROM alerts WHERE related_product_id = $1 AND type IN ($2, $3) AND is_resolved = FALSE',
    //     [productId, 'low_stock', 'over_stock']
    //   );
    // }

    await dbClient.query(
      `UPDATE alerts
      SET is_resolved = TRUE, updated_at = CURRENT_TIMESTAMP
      WHERE related_product_id = $1
        AND type IN ($2, $3)
        AND is_resolved = FALSE`,
      [productId, "low_stock", "over_stock"]
    );
  } catch (err) {
    console.error("Error updating stock alert:", err);
    // Không throw để không ảnh hưởng đến transaction chính
  }
}

// Export để dùng ở routes khác
module.exports.checkAndCreateStockAlert = checkAndCreateStockAlert;

// GET list alerts
router.get("/", async (req, res, next) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const type = req.query.type;
    const isResolved = req.query.is_resolved; // true/false/undefined
    const offset = (page - 1) * limit;

    let query = `
      SELECT a.alert_id, a.type, a.message, a.severity, a.is_resolved, a.created_at, a.related_product_id,
             p.name AS product_name 
      FROM alerts a 
      LEFT JOIN products p ON a.related_product_id = p.product_id 
      WHERE 1=1
    `;
    const params = [];

    if (type) {
      query += ` AND a.type = $${params.length + 1}`;
      params.push(type);
    }

    if (isResolved !== undefined) {
      query += ` AND a.is_resolved = $${params.length + 1}`;
      params.push(isResolved === "true" || isResolved === true);
    }

    query += ` ORDER BY a.alert_id DESC LIMIT $${params.length + 1} OFFSET $${
      params.length + 2
    }`;
    params.push(limit, offset);

    const { rows } = await pool.query(query, params);

    // Count total với cùng filter
    let countQuery = "SELECT COUNT(*) FROM alerts WHERE 1=1";
    const countParams = [];
    if (type) {
      countQuery += ` AND type = $${countParams.length + 1}`;
      countParams.push(type);
    }
    if (isResolved !== undefined) {
      countQuery += ` AND is_resolved = $${countParams.length + 1}`;
      countParams.push(isResolved === "true" || isResolved === true);
    }

    const { rows: countRows } = await pool.query(countQuery, countParams);
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// Resolve alert
router.put(
  "/:id/resolve",
  auth(["admin", "client"]),
  async (req, res, next) => {
    try {
      const { rows } = await pool.query(
        "UPDATE alerts SET is_resolved = TRUE WHERE alert_id = $1 RETURNING *",
        [req.params.id]
      );
      res.json({ success: true, data: rows[0] });
    } catch (err) {
      next(err);
    }
  }
);

// Unresolve alert (đổi về chưa xử lý)
router.put(
  "/:id/unresolve",
  auth(["admin", "client"]),
  async (req, res, next) => {
    try {
      const { rows } = await pool.query(
        "UPDATE alerts SET is_resolved = FALSE WHERE alert_id = $1 RETURNING *",
        [req.params.id]
      );
      res.json({ success: true, data: rows[0] });
    } catch (err) {
      next(err);
    }
  }
);

// Generate alerts (low stock, over stock, promotions)
router.post(
  "/generate",
  auth(["admin", "client"]),
  async (req, res, next) => {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      const created = [];

      // Low stock
      const { rows: lowStock } = await client.query(
        `SELECT product_id, name, stock, minimum_inventory
       FROM products
       WHERE minimum_inventory IS NOT NULL AND stock < minimum_inventory`
      );
      for (const p of lowStock) {
        const type = "low_stock";
        const message = `Sản phẩm "${p.name}" dưới mức tồn tối thiểu (${p.stock}/${p.minimum_inventory})`;
        const severity = "high";
        const exists = await client.query(
          "SELECT alert_id FROM alerts WHERE type = $1 AND message = $2 AND is_resolved = FALSE LIMIT 1",
          [type, message]
        );
        if (!exists.rows.length) {
          const ins = await client.query(
            `INSERT INTO alerts (type, message, severity, is_resolved, related_product_id)
           VALUES ($1, $2, $3, FALSE, $4) RETURNING *`,
            [type, message, severity, p.product_id]
          );
          created.push(ins.rows[0]);
        }
      }

      // Over stock
      const { rows: overStock } = await client.query(
        `SELECT product_id, name, stock, maximum_inventory
       FROM products
       WHERE maximum_inventory IS NOT NULL AND stock > maximum_inventory`
      );
      for (const p of overStock) {
        const type = "over_stock";
        const message = `Sản phẩm "${p.name}" vượt tồn tối đa (${p.stock}/${p.maximum_inventory})`;
        const severity = "medium";
        const exists = await client.query(
          "SELECT alert_id FROM alerts WHERE type = $1 AND message = $2 AND is_resolved = FALSE LIMIT 1",
          [type, message]
        );
        if (!exists.rows.length) {
          const ins = await client.query(
            `INSERT INTO alerts (type, message, severity, is_resolved, related_product_id)
           VALUES ($1, $2, $3, FALSE, $4) RETURNING *`,
            [type, message, severity, p.product_id]
          );
          created.push(ins.rows[0]);
        }
      }

      // Promotions expired and expiring soon
      const { rows: promosExpired } = await client.query(
        `SELECT promotion_id, name, end_date
       FROM promotions
       WHERE end_date < NOW()`
      );
      for (const pr of promosExpired) {
        const type = "promotion_expired";
        const message = `Khuyến mãi "${pr.name}" đã hết hạn (đến ${pr.end_date
          .toISOString()
          .slice(0, 10)})`;
        const severity = "low";
        const exists = await client.query(
          "SELECT alert_id FROM alerts WHERE type = $1 AND message = $2 AND is_resolved = FALSE LIMIT 1",
          [type, message]
        );
        if (!exists.rows.length) {
          const ins = await client.query(
            `INSERT INTO alerts (type, message, severity, is_resolved)
           VALUES ($1, $2, $3, FALSE) RETURNING *`,
            [type, message, severity]
          );
          created.push(ins.rows[0]);
        }
      }

      const { rows: promosExpiring } = await client.query(
        `SELECT promotion_id, name, end_date
       FROM promotions
       WHERE end_date >= NOW() AND end_date < NOW() + INTERVAL '7 days'`
      );
      for (const pr of promosExpiring) {
        const type = "promotion_expiring";
        const message = `Khuyến mãi "${pr.name}" sắp hết hạn (đến ${pr.end_date
          .toISOString()
          .slice(0, 10)})`;
        const severity = "low";
        const exists = await client.query(
          "SELECT alert_id FROM alerts WHERE type = $1 AND message = $2 AND is_resolved = FALSE LIMIT 1",
          [type, message]
        );
        if (!exists.rows.length) {
          const ins = await client.query(
            `INSERT INTO alerts (type, message, severity, is_resolved)
           VALUES ($1, $2, $3, FALSE) RETURNING *`,
            [type, message, severity]
          );
          created.push(ins.rows[0]);
        }
      }

      // Tự động cleanup cảnh báo đã xử lý cũ hơn 30 ngày (giới hạn 50 bản ghi mỗi lần)
      const { rows: deletedRows } = await client.query(
        `DELETE FROM alerts 
       WHERE alert_id IN (
         SELECT alert_id FROM alerts 
         WHERE is_resolved = TRUE 
         AND updated_at < NOW() - INTERVAL '30 days'
         ORDER BY updated_at ASC
         LIMIT 50
       )
       RETURNING alert_id`
      );

      await client.query("COMMIT");
      res.json({
        success: true,
        created: created.length,
        cleaned: deletedRows.length,
        data: created,
      });
    } catch (err) {
      await client.query("ROLLBACK");
      next(err);
    } finally {
      client.release();
    }
  }
);

// Cleanup alerts đã xử lý cũ hơn 30 ngày (giới hạn 100 bản ghi mỗi lần để tránh quá tải)
router.post("/cleanup", auth(["admin"]), async (req, res, next) => {
  try {
    const limit = parseInt(req.query.limit) || 100;
    const { rows } = await pool.query(
      `DELETE FROM alerts 
       WHERE alert_id IN (
         SELECT alert_id FROM alerts 
         WHERE is_resolved = TRUE 
         AND updated_at < NOW() - INTERVAL '30 days'
         ORDER BY updated_at ASC
         LIMIT $1
       )
       RETURNING alert_id`
    );
    res.json({
      success: true,
      deleted: rows.length,
      message: `Đã xóa ${rows.length} cảnh báo cũ`,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
module.exports.checkAndCreateStockAlert = checkAndCreateStockAlert;
