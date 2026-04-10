// backend/src/routes/purchases.js
const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");
const { checkAndCreateStockAlert } = require("./alerts");
const PDFDocument = require("pdfkit");
const { PassThrough } = require("stream");

// ======= GET list purchases (optional date range, product, search) =======
router.get("/", async (req, res, next) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 100000;
    const offset = (page - 1) * limit;
    const { start_date, end_date, product_id, q } = req.query;

    const params = [];
    let i = 1;
    let where = "WHERE 1=1";

    if (start_date && end_date) {
      where += ` AND DATE(p.purchase_date) BETWEEN $${i++} AND $${i++}`;
      params.push(start_date, end_date);
    }
    if (product_id) {
      where += ` AND EXISTS (SELECT 1 FROM purchase_details pd0 WHERE pd0.purchase_id = p.purchase_id AND pd0.product_id = $${i++})`;
      params.push(Number(product_id));
    }
    if (q && String(q).trim()) {
      where += ` AND p.purchase_number ILIKE $${i++}`;
      params.push(`%${String(q).trim()}%`);
    }

    const listSql = `
      SELECT p.purchase_id, p.purchase_number, p.purchase_date, p.total_amount, p.status,
             e.name AS employee_name, pm.name AS payment_method_name
       FROM purchases p
       LEFT JOIN employees e ON p.employee_id = e.employee_id
       LEFT JOIN payment_methods pm ON p.payment_method_id = pm.payment_method_id
       ${where}
       ORDER BY p.purchase_id DESC
       LIMIT $${i++} OFFSET $${i++}`;
    params.push(limit, offset);

    const { rows } = await pool.query(listSql, params);

    const countSql = `SELECT COUNT(*)::int AS c FROM purchases p ${where}`;
    const countParams = params.slice(0, params.length - 2);
    const { rows: countRows } = await pool.query(countSql, countParams);
    const total = countRows[0]?.c ?? 0;

    res.json({ success: true, data: rows, pagination: { page, limit, total } });
  } catch (err) {
    next(err);
  }
});

// ======= GET purchase slip PDF (must be before /:id) =======
router.get("/:id/invoice", auth(["admin", "client"]), async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT p.*, e.name AS employee_name, pm.name AS payment_method_name,
              pd.quantity, pd.unit_cost, prod.product_id, prod.name AS product_name
       FROM purchases p
       LEFT JOIN employees e ON p.employee_id = e.employee_id
       LEFT JOIN payment_methods pm ON p.payment_method_id = pm.payment_method_id
       LEFT JOIN purchase_details pd ON p.purchase_id = pd.purchase_id
       LEFT JOIN products prod ON pd.product_id = prod.product_id
       WHERE p.purchase_id = $1`,
      [req.params.id]
    );
    if (!rows.length)
      return res.status(404).json({ success: false, error: "Not found" });

    const head = rows[0];
    const doc = new PDFDocument({ size: "A4", margin: 40 });
    const stream = new PassThrough();
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader(
      "Content-Disposition",
      `attachment; filename=purchase-${head.purchase_number}.pdf`
    );
    doc.pipe(stream);

    doc.fontSize(18).text("PHIẾU NHẬP KHO", { align: "center" });
    doc.moveDown(0.5);
    doc.fontSize(11);
    doc.text(`Số phiếu: ${head.purchase_number}`);
    doc.text(`Ngày: ${head.purchase_date}`);
    doc.text(`Người tạo: ${head.employee_name || "—"}`);
    doc.text(`Thanh toán: ${head.payment_method_name || "—"}`);
    doc.text(`Trạng thái: ${head.status || "—"}`);
    doc.moveDown();
    doc.font("Helvetica-Bold").text("Chi tiết");
    doc.font("Helvetica");
    let sum = 0;
    rows.forEach((r) => {
      if (r.product_id == null) return;
      const line = Number(r.quantity || 0) * Number(r.unit_cost || 0);
      sum += line;
      doc.text(
        `- ${r.product_name}  SL: ${r.quantity}  ĐG: ${Number(r.unit_cost).toLocaleString()}  = ${line.toLocaleString()}`
      );
    });
    doc.moveDown();
    doc.font("Helvetica-Bold").text(`Tổng: ${sum.toLocaleString()} VND`, {
      align: "right",
    });
    doc.end();
    stream.pipe(res);
  } catch (err) {
    next(err);
  }
});

// ======= GET detail =======
router.get("/:id", async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT p.*, e.name AS employee_name, pm.name AS payment_method_name,
              pd.quantity, pd.unit_cost, prod.product_id, prod.name AS product_name, s.name AS supplier_name
       FROM purchases p
       LEFT JOIN employees e ON p.employee_id = e.employee_id
       LEFT JOIN payment_methods pm ON p.payment_method_id = pm.payment_method_id
       LEFT JOIN purchase_details pd ON p.purchase_id = pd.purchase_id
       LEFT JOIN products prod ON pd.product_id = prod.product_id
       LEFT JOIN suppliers s ON prod.supplier_id = s.supplier_id
       WHERE p.purchase_id = $1`,
      [req.params.id]
    );

    if (!rows.length)
      return res.status(404).json({ success: false, error: "Not found" });

    const head = rows[0];
    const details = rows.map((r) => ({
      product_id: r.product_id,
      product_name: r.product_name,
      quantity: Number(r.quantity),
      unit_cost: Number(r.unit_cost),
      supplier_name: r.supplier_name || null,
    }));

    const purchase = {
      purchase_id: head.purchase_id,
      purchase_number: head.purchase_number,
      purchase_date: head.purchase_date,
      employee_id: head.employee_id,
      employee_name: head.employee_name,
      payment_method_id: head.payment_method_id,
      payment_method_name: head.payment_method_name,
      total_amount: Number(head.total_amount),
      amount_paid: Number(head.amount_paid || head.total_amount || 0),
      status: head.status,
      details,
    };

    res.json({ success: true, data: purchase });
  } catch (err) {
    next(err);
  }
});

// ======= POST create (giữ nguyên logic của bạn) =======
// ======= POST create purchase (ĐẦY ĐỦ, AN TOÀN, DỄ HIỂU) =======
router.post("/", auth(["admin", "client"]), async (req, res, next) => {
  const client = await pool.connect();
  try {
    const {
      purchase_number,
      payment_method_id,
      details,
      status: incomingStatus,
    } = req.body;

    const employee_id = req.user.id;

    // ✅ Status linh hoạt: tiền mặt = completed, PayOS = pending
    const status = incomingStatus || "pending";

    if (!Array.isArray(details) || details.length === 0) {
      return res.status(400).json({
        success: false,
        error: "Cần ít nhất 1 sản phẩm để nhập kho",
      });
    }

    // Chuẩn hóa details
    const safeDetails = details.map((d) => ({
      product_id: Number(d.product_id),
      quantity: Math.max(1, Number(d.quantity || 1)),
      unit_cost: Math.max(0, Number(d.unit_cost || 0)),
    }));

    const total_amount = safeDetails.reduce(
      (sum, d) => sum + d.quantity * d.unit_cost,
      0
    );

    await client.query("BEGIN");

    // ==============================
    //  INSERT PURCHASE
    // ==============================
    const { rows: purchaseRows } = await client.query(
      `INSERT INTO purchases (
        purchase_number, 
        employee_id, 
        purchase_date, 
        total_amount, 
        amount_paid, 
        payment_method_id, 
        status, 
        created_at, 
        updated_at
      )
      VALUES ($1, $2, CURRENT_TIMESTAMP, $3, $3, $4, $5, NOW(), NOW())
      RETURNING purchase_id, purchase_number`,
      [
        purchase_number || `PN-${Date.now()}`,
        employee_id,
        total_amount,
        payment_method_id, // null hoặc id
        status, // <-- ❗quan trọng: pending hay completed
      ]
    );

    const purchase_id = purchaseRows[0].purchase_id;
    const createdPurchaseNumber = purchaseRows[0].purchase_number;

    // ==============================
    // INSERT DETAILS + UPDATE STOCK
    // ==============================
    for (const d of safeDetails) {
      // Nếu đơn giá không được gửi → lấy từ cost_price hiện tại
      if (d.unit_cost === undefined || d.unit_cost === null) {
        const { rows: pr } = await client.query(
          "SELECT COALESCE(cost_price,0) AS cost_price FROM products WHERE product_id = $1",
          [d.product_id]
        );
        d.unit_cost = Number(pr?.[0]?.cost_price || 0);
      }

      // Insert chi tiết
      await client.query(
        `INSERT INTO purchase_details 
           (purchase_id, product_id, quantity, unit_cost, created_at)
         VALUES ($1, $2, $3, $4, NOW())`,
        [purchase_id, d.product_id, d.quantity, d.unit_cost]
      );

      // Trigger đã tăng tồn kho → chỉ cập nhật cost_price
      await client.query(
        `UPDATE products
         SET cost_price = $1,
             updated_at = NOW()
         WHERE product_id = $2`,
        [d.unit_cost, d.product_id]
      );

      // === UPDATE ALERT SAU KHI TRIGGER CỘNG STOCK ===
    }
    for (const d of safeDetails) {
      await checkAndCreateStockAlert(pool, d.product_id);
    }
    await client.query("COMMIT");

    console.log(
      `✅ [PURCHASE CREATED] ID=${purchase_id} - STATUS=${status} - TOTAL=${total_amount}`
    );

    return res.status(201).json({
      success: true,
      message: "Đã tạo phiếu nhập",
      data: {
        purchase_id,
        purchase_number: createdPurchaseNumber,
      },
    });
  } catch (err) {
    await client.query("ROLLBACK");
    console.error("❌ [PURCHASE ERROR]:", err);
    next(err);
  } finally {
    client.release();
  }
});

// ======= ✅ PUT update (ĐÃ FIX THEO OPTION G & Y) =======
router.put("/:id", auth(["admin", "client"]), async (req, res, next) => {
  const client = await pool.connect();
  try {
    const { payment_method_id, status, details } = req.body;

    if (!Array.isArray(details) || details.length === 0) {
      return res
        .status(400)
        .json({ success: false, error: "Phiếu phải có ít nhất 1 sản phẩm" });
    }

    // Tính lại total_amount
    const safeDetails = details.map((d) => ({
      product_id: Number(d.product_id),
      quantity: Math.max(1, Number(d.quantity || 1)),
      unit_cost: Math.max(0, Number(d.unit_cost ?? 0)),
    }));
    const total_amount = safeDetails.reduce(
      (s, d) => s + d.quantity * d.unit_cost,
      0
    );

    await client.query("BEGIN");

    // Update purchases
    await client.query(
      `UPDATE purchases SET
         payment_method_id = $1,
         status = $2,
         total_amount = $3,
         updated_at = NOW()
       WHERE purchase_id = $4`,
      [payment_method_id, status, total_amount, req.params.id]
    );

    // Clear old details
    await client.query("DELETE FROM purchase_details WHERE purchase_id = $1", [
      req.params.id,
    ]);

    // Insert new details
    for (const d of safeDetails) {
      await client.query(
        `INSERT INTO purchase_details (purchase_id, product_id, quantity, unit_cost)
         VALUES ($1, $2, $3, $4)`,
        [req.params.id, d.product_id, d.quantity, d.unit_cost]
      );
    }

    await client.query("COMMIT");
    res.json({ success: true });
  } catch (err) {
    await client.query("ROLLBACK");
    next(err);
  } finally {
    client.release();
  }
});

// ======= DELETE =======
// router.delete('/:id', auth(['admin']), async (req, res, next) => {
//   // ... giữ nguyên như bạn gửi
// });

// module.exports = router;

// ======= DELETE purchase (xoá details trước) =======
router.delete("/:id", auth(["admin"]), async (req, res, next) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("DELETE FROM purchase_details WHERE purchase_id = $1", [
      req.params.id,
    ]);
    const { rows } = await client.query(
      "DELETE FROM purchases WHERE purchase_id = $1 RETURNING *",
      [req.params.id]
    );
    if (!rows.length) {
      await client.query("ROLLBACK");
      return res.status(404).json({ success: false, error: "Not found" });
    }
    await client.query("COMMIT");
    res.json({ success: true, message: "Deleted" });
  } catch (err) {
    await client.query("ROLLBACK");
    next(err);
  } finally {
    client.release();
  }
});

module.exports = router;
