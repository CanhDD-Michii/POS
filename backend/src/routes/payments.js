// backend/src/routes/payments.js
const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");
const payos = require("../utils/payos");
const QRCode = require("qrcode");

// ===============================
// CREATE PAYMENT LINK + QR PNG
// ===============================
router.post("/payos", auth(["admin", "client"]), async (req, res, next) => {
  try {
    const { orderNumber, purchaseNumber, type = "order", amount, description, returnUrl, cancelUrl } = req.body;

    const payCode = Date.now();

    const body = {
      orderCode: payCode,
      amount: Number(amount),
      description: description?.slice(0, 25) || "Payment",
      returnUrl,
      cancelUrl,
    };

    const result = await payos.createPaymentLink(body);

    // RAW QR từ PayOS
    const rawQR = result.qrCode;

    // Convert thành PNG base64
    const qr_base64 = rawQR
      ? await QRCode.toDataURL(rawQR)
      : null;

    // Lưu DB
    await pool.query(
      `INSERT INTO payments (
        context_type, order_number, purchase_number,
        pay_code, provider, reference, amount,
        status, checkout_url, qr_base64, data,
        created_at, updated_at
      ) VALUES ($1,$2,$3,$4,'payos',$5,$6,'pending',$7,$8,$9,NOW(),NOW())
      ON CONFLICT (pay_code)
      DO UPDATE SET
        reference = EXCLUDED.reference,
        checkout_url = EXCLUDED.checkout_url,
        qr_base64 = EXCLUDED.qr_base64,
        data = EXCLUDED.data,
        updated_at = NOW()`,
      [
        type,
        orderNumber || null,
        purchaseNumber || null,
        payCode,
        result.paymentLinkId,
        amount,
        result.checkoutUrl,
        qr_base64,
        result
      ]
    );

    res.json({
      success: true,
      data: {
        payCode,
        orderNumber,
        purchaseNumber,
        amount,
        checkoutUrl: result.checkoutUrl,
        qr_base64,
        status: "pending"
      }
    });

  } catch (err) {
    console.error("PAYOS ERROR", err);
    next(err);
  }
});

// LẤY PAYMENT MỚI NHẤT
router.get("/latest", auth(["admin", "client"]), async (req, res, next) => {
  try {
    const { orderNumber, purchaseNumber } = req.query;

    const { rows } = await pool.query(
      `SELECT * FROM payments
       WHERE (order_number=$1 OR $1 IS NULL)
       AND (purchase_number=$2 OR $2 IS NULL)
       ORDER BY created_at DESC
       LIMIT 1`,
      [orderNumber || null, purchaseNumber || null]
    );

    res.json({ success: true, data: rows[0] || null });
  } catch (err) {
    next(err);
  }
});

// GET PAYMENT BY CODE
router.get("/:code", auth(["admin", "client"]), async (req, res, next) => {
  try {
    const code = Number(req.params.code);
    const { rows } = await pool.query("SELECT * FROM payments WHERE pay_code=$1", [code]);
    res.json({ success: true, data: rows[0] || null });
  } catch (err) {
    next(err);
  }
});

// ====================== WEBHOOK PAYOS ======================
// WEBHOOK PAYOS – cập nhật payments + orders/purchases
router.post("/payos/webhook", async (req, res) => {
  try {
    console.log("WEBHOOK RECEIVED:", req.body);

    const { code, data } = req.body;
    if (!data || !data.orderCode) {
      console.warn("WEBHOOK MISSING orderCode");
      return res.status(400).json({ success: false, message: "Missing orderCode" });
    }

    const payCode = data.orderCode;

    // Quy ước: code === "00" => thanh toán thành công
    const paymentStatus =
      code === "00" && data.code === "00" ? "completed" : "pending";

    // 1. Cập nhật bảng payments và lấy lại context_type + order_number + purchase_number
    const { rows } = await pool.query(
      `
      UPDATE payments
      SET status = $1,
          data   = $2,
          updated_at = NOW()
      WHERE pay_code = $3
      RETURNING context_type, order_number, purchase_number
      `,
      [paymentStatus, data, payCode]
    );

    if (!rows.length) {
      console.warn("WEBHOOK: Không tìm thấy payment với pay_code =", payCode);
      return res.json({ success: true, message: "No payment row matched" });
    }

    const p = rows[0];

    // 2. Nếu thanh toán thành công -> cập nhật đơn hàng / phiếu nhập
    if (paymentStatus === "completed") {
      if (p.context_type === "order" && p.order_number) {
        await pool.query(
          `
          UPDATE orders
          SET status = 'completed',
              updated_at = NOW()
          WHERE order_number = $1
          `,
          [p.order_number]
        );
        console.log("WEBHOOK: Updated order", p.order_number);
      }

      if (p.context_type === "purchase" && p.purchase_number) {
        await pool.query(
          `
          UPDATE purchases
          SET status = 'completed',
              updated_at = NOW()
          WHERE purchase_number = $1
          `,
          [p.purchase_number]
        );
        console.log("WEBHOOK: Updated purchase", p.purchase_number);
      }
    }

    return res.json({ success: true });
  } catch (err) {
    console.error("WEBHOOK ERROR:", err);
    return res.status(500).json({ success: false });
  }
});




module.exports = router;
