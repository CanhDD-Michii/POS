// backend/src/routes/reports.js (Cập nhật)
const express = require("express");
const router = express.Router();
const pool = require("../db");
const auth = require("../middleware/auth");
const { exportToCSV } = require("../utils/export");
const { exportPDFTableStream } = require("../utils/exportPDFTableStream");
const { exportCSVStream } = require("../utils/exportCSVStream");
const PDFDocument = require("pdfkit");
const path = require("path");

const {
  exportInventoryReportPDF,
} = require("../utils/exportInventoryReportPDF");
const { exportToPDFStream } = require("../utils/exportToPDFStream");

// Báo cáo tồn kho (đã có)
router.get("/inventory", async (req, res, next) => {
  try {
    const mode = req.query.mode || "";

    let wherePur = "1=1";
    let whereOrd = "1=1";

    if (mode === "day") {
      wherePur = "DATE(pur.purchase_date) = CURRENT_DATE";
      whereOrd = "DATE(o.order_date) = CURRENT_DATE";
    } else if (mode === "month") {
      wherePur =
        "DATE_TRUNC('month', pur.purchase_date) = DATE_TRUNC('month', CURRENT_DATE)";
      whereOrd =
        "DATE_TRUNC('month', o.order_date) = DATE_TRUNC('month', CURRENT_DATE)";
    } else if (mode === "year") {
      wherePur =
        "DATE_TRUNC('year', pur.purchase_date) = DATE_TRUNC('year', CURRENT_DATE)";
      whereOrd =
        "DATE_TRUNC('year', o.order_date) = DATE_TRUNC('year', CURRENT_DATE)";
    } else if (mode === "all") {
      // không lọc gì
    }

    const sql = `
      SELECT 
        p.product_id,
        p.name AS product_name,
        p.stock,
        p.minimum_inventory,

        /* Tổng nhập theo bộ lọc */
        COALESCE(pur.total_purchased, 0) AS total_purchased,

        /* Tổng bán theo bộ lọc */
        COALESCE(ord.total_sold, 0) AS total_sold,

        a.message AS alert_message

      FROM products p

      /* SUBQUERY PURCHASE */
      LEFT JOIN (
        SELECT pd.product_id, SUM(pd.quantity) AS total_purchased
        FROM purchase_details pd
        JOIN purchases pur ON pur.purchase_id = pd.purchase_id
        WHERE ${wherePur}
        GROUP BY pd.product_id
      ) pur ON pur.product_id = p.product_id

      /* SUBQUERY ORDER */
      LEFT JOIN (
        SELECT od.product_id, SUM(od.quantity) AS total_sold
        FROM order_details od
        JOIN orders o ON o.order_id = od.order_id
        WHERE ${whereOrd}
        GROUP BY od.product_id
      ) ord ON ord.product_id = p.product_id

      /* ALERT */
      LEFT JOIN alerts a 
        ON a.related_product_id = p.product_id 
        AND a.is_resolved = FALSE

      ORDER BY p.product_id;
    `;

    const { rows } = await pool.query(sql);
    res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
});

// Export inventory report to CSV
router.get(
  "/inventory/export",
  auth(["admin", "client"]),
  async (req, res, next) => {
    try {
      const { rows } = await pool.query(`
      SELECT 
        p.name AS ten_san_pham,
        p.stock AS ton_kho,
        COALESCE(SUM(pd.quantity),0) AS da_nhap,
        COALESCE(SUM(od.quantity),0) AS da_ban,
        p.minimum_inventory AS ton_toi_thieu
      FROM products p
      LEFT JOIN purchase_details pd ON p.product_id = pd.product_id
      LEFT JOIN order_details od ON p.product_id = od.product_id
      GROUP BY p.product_id
    `);

      exportCSVStream(
        res,
        "Bao_cao_ton_kho",
        [
          { label: "Sản phẩm", key: "ten_san_pham" },
          { label: "Tồn kho", key: "ton_kho" },
          { label: "Đã nhập", key: "da_nhap" },
          { label: "Đã bán", key: "da_ban" },
          { label: "Tồn tối thiểu", key: "ton_toi_thieu" },
        ],
        rows
      );
    } catch (err) {
      next(err);
    }
  }
);

//New CSV export route
router.post("/inventory/csv", auth(["admin"]), (req, res) => {
  const { displayData } = req.body;

  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader(
    "Content-Disposition",
    "attachment; filename=bao_cao_ton_kho.csv"
  );
  res.write("\uFEFF");

  res.write("Sản phẩm,Tồn kho,Đã nhập,Đã bán,Tồn tối thiểu\n");

  displayData.forEach((p) => {
    res.write(
      `${p.product_name},${p.stock},${p.total_purchased},${p.total_sold},${p.minimum_inventory}\n`
    );
  });

  res.end();
});

router.post("/inventory/export-pdf", auth(["admin"]), async (req, res) => {
  const { filters, displayData } = req.body;

  const data = displayData.map((p) => ({
    name: p.product_name,
    stock: Number(p.stock || 0),
    imported: Number(p.total_purchased || 0),
    sold: Number(p.total_sold || 0),
    min: Number(p.minimum_inventory || 0),
  }));

  const mode = filters?.mode;

  const timeLabel =
    {
      day: "Theo ngày",
      month: "Theo tháng",
      year: "Theo năm",
      all: "Toàn thời gian",
    }[mode] || "Không xác định";

  const doc = new PDFDocument({ size: "A4", margin: 50 });

  const fontRegular = path.join(__dirname, "..", "fonts/Roboto-Regular.ttf");
  const fontBold = path.join(__dirname, "..", "fonts/Roboto-Bold.ttf");

  res.setHeader("Content-Type", "application/pdf");
  res.setHeader(
    "Content-Disposition",
    "attachment; filename=bao_cao_ton_kho.pdf"
  );

  doc.pipe(res);

  // HEADER TITLE
  doc.font(fontBold).fontSize(22).text("BÁO CÁO TỒN KHO", { align: "center" });
  doc.moveDown(1);

  // TIME RANGE
  doc
    .font(fontRegular)
    .fontSize(12)
    .text(`Khoảng thời gian: ${timeLabel}`, { align: "center" });
  doc.moveDown(1.5);

  // Divider
  doc.moveTo(50, doc.y).lineTo(545, doc.y).stroke();
  doc.moveDown(1);

  // SUMMARY
  const totalImported = data.reduce((s, r) => s + r.imported, 0);
  const totalSold = data.reduce((s, r) => s + r.sold, 0);
  const totalStock = data.reduce((s, r) => s + r.stock, 0);

  doc.font(fontBold).fontSize(14).text("1. TỔNG QUAN");
  doc.moveDown(0.5);

  doc.font(fontRegular).fontSize(12);
  doc.text(`• Tổng nhập: ${totalImported}`);
  doc.text(`• Tổng bán: ${totalSold}`);
  doc.text(`• Tồn cuối kỳ: ${totalStock}`);
  doc.moveDown(1);

  // DETAILS SECTION
  doc.font(fontBold).fontSize(14).text("2. CHI TIẾT TỒN KHO");
  doc.moveDown(0.7);

  data.forEach((p) => {
    const status = p.stock < p.min ? "⚠ Thiếu hàng" : "Đủ hàng";

    // Tên sản phẩm in đậm
    doc.font(fontBold).text(`• ${p.name}`);
    doc
      .font(fontRegular)
      .text(
        `   Nhập: ${p.imported}   |   Bán: ${p.sold}   |   Tồn: ${p.stock}   |   ${status}`
      );
    doc.moveDown(0.4);
  });

  doc.end();
});

// Báo cáo doanh thu/chi phí
// Báo cáo doanh thu / chi phí (CHUẨN - chỉ tính từ financial_transactions)
router.get(
  "/revenue-expense",
  auth(["admin", "client"]),
  async (req, res, next) => {
    try {
      const { start_date, end_date, supplier_id } = req.query;
      const conditions = [];
      const params = [];
      let i = 1;

      // Filter theo ngày
      if (start_date && end_date) {
        conditions.push(`ft.transaction_date BETWEEN $${i++} AND $${i++}`);
        params.push(start_date, end_date);
      }

      // Lọc theo supplier
      if (supplier_id) {
        conditions.push(`ft.supplier_id = $${i++}`);
        params.push(supplier_id);
      }

      const where = conditions.length
        ? `WHERE ${conditions.join(" AND ")}`
        : "";

      const query = `
        SELECT 
          s.name AS supplier_name,

          -- Doanh thu hoàn tất
          SUM(CASE WHEN ft.type='income' AND ft.status='completed' 
                   THEN ft.amount ELSE 0 END) AS revenue,

          -- Chi phí hoàn tất
          SUM(CASE WHEN ft.type='expense' AND ft.status='completed' 
                   THEN ft.amount ELSE 0 END) AS expense,

          -- Công nợ phải thu
          SUM(CASE WHEN ft.type='income' AND ft.status='pending' 
                   THEN ft.amount ELSE 0 END) AS debt_income,

          -- Công nợ phải trả
          SUM(CASE WHEN ft.type='expense' AND ft.status='pending' 
                   THEN ft.amount ELSE 0 END) AS debt_expense

        FROM financial_transactions ft
        LEFT JOIN suppliers s ON ft.supplier_id = s.supplier_id
        ${where}
        GROUP BY s.name
        ORDER BY s.name;
      `;

      const { rows } = await pool.query(query, params);
      res.json({ success: true, data: rows });
    } catch (err) {
      next(err);
    }
  }
);

// Báo cáo giao dịch tài chính
router.get("/financial-transactions", async (req, res, next) => {
  const { start_date, end_date, type } = req.query;
  try {
    let query = `
        SELECT ft.type, ft.amount, ft.transaction_date, ft.status,
              o.order_number, pur.purchase_number, c.name AS customer_name, s.name AS supplier_name,
              e.name AS employee_name, pm.name AS payment_method_name
        FROM financial_transactions ft
        LEFT JOIN orders o ON ft.related_order_id = o.order_id
        LEFT JOIN purchases pur ON ft.related_purchase_id = pur.purchase_id
        LEFT JOIN customers c ON ft.customer_id = c.customer_id
        LEFT JOIN suppliers s ON ft.supplier_id = s.supplier_id
        LEFT JOIN employees e ON ft.employee_id = e.employee_id
        LEFT JOIN payment_methods pm ON ft.payment_method_id = pm.payment_method_id
        WHERE 1=1
      `;
    const params = [];

    if (start_date && end_date) {
      query += ` AND ft.transaction_date BETWEEN $${params.length + 1} AND $${
        params.length + 2
      }`;
      params.push(start_date, end_date);
    }
    if (type) {
      query += ` AND ft.type = $${params.length + 1}`;
      params.push(type);
    }

    const { rows } = await pool.query(query, params);
    res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
});

/**
 * Stock movement history for one product (inbound purchases + outbound orders).
 */
router.get("/product-movements/:productId", async (req, res, next) => {
  try {
    const productId = Number(req.params.productId);
    if (!Number.isFinite(productId)) {
      return res.status(400).json({ success: false, error: "Invalid product" });
    }
    const { start_date, end_date } = req.query;
    const params = [productId];
    let i = 2;
    let dateIn = "";
    let dateOut = "";
    if (start_date && end_date) {
      dateIn = ` AND DATE(pur.purchase_date) BETWEEN $${i} AND $${i + 1}`;
      dateOut = ` AND DATE(o.order_date) BETWEEN $${i} AND $${i + 1}`;
      params.push(start_date, end_date);
      i += 2;
    }

    const sql = `
      SELECT * FROM (
        SELECT 
          'in'::text AS direction,
          pur.purchase_date AS movement_at,
          pur.purchase_number AS document_ref,
          pd.quantity,
          pd.unit_cost AS unit_price,
          (pd.quantity * pd.unit_cost)::numeric AS line_total
        FROM purchase_details pd
        JOIN purchases pur ON pur.purchase_id = pd.purchase_id
        WHERE pd.product_id = $1 ${dateIn}
        UNION ALL
        SELECT 
          'out'::text,
          o.order_date,
          o.order_number,
          od.quantity,
          od.price,
          (od.quantity * od.price)::numeric
        FROM order_details od
        JOIN orders o ON o.order_id = od.order_id
        WHERE od.product_id = $1 ${dateOut}
      ) m
      ORDER BY movement_at DESC NULLS LAST, document_ref DESC
    `;
    const { rows } = await pool.query(sql, params);
    res.json({ success: true, data: rows });
  } catch (err) {
    next(err);
  }
});

/**
 * Totals for completed income vs expense financial transactions in range.
 */
router.get("/revenue-summary", auth(["admin", "client"]), async (req, res, next) => {
  try {
    const { start_date, end_date } = req.query;
    const params = [];
    let where = "WHERE 1=1";
    if (start_date && end_date) {
      where += ` AND ft.transaction_date::date BETWEEN $1 AND $2`;
      params.push(start_date, end_date);
    }
    const q = `
      SELECT 
        COALESCE(SUM(CASE WHEN ft.type = 'income' AND ft.status = 'completed' THEN ft.amount ELSE 0 END), 0)::numeric AS total_in,
        COALESCE(SUM(CASE WHEN ft.type = 'expense' AND ft.status = 'completed' THEN ft.amount ELSE 0 END), 0)::numeric AS total_out
      FROM financial_transactions ft
      ${where}
    `;
    const { rows } = await pool.query(q, params);
    res.json({ success: true, data: rows[0] || { total_in: 0, total_out: 0 } });
  } catch (err) {
    next(err);
  }
});

// Export financial report to CSV
router.get(
  "/financial-transactions/export",
  auth(["admin"]),
  async (req, res, next) => {
    try {
      const { rows } = await pool.query(
        `SELECT ft.type, ft.amount, ft.transaction_date, ft.status, pm.name AS payment_method_name
        FROM financial_transactions ft
        LEFT JOIN payment_methods pm ON ft.payment_method_id = pm.payment_method_id`
      );
      const filePath = exportToCSV(
        rows,
        ["type", "amount", "transaction_date", "status", "payment_method_name"],
        "./reports/financial-transactions.csv"
      );
      res.download(filePath);
    } catch (err) {
      next(err);
    }
  }
);

router.post(
  "/inventory/export-pdf",
  auth(["admin"]),
  async (req, res, next) => {
    try {
      const data = req.body; // nhận dữ liệu frontend đang hiển thị
      exportInventoryReportPDF(res, data);
    } catch (err) {
      next(err);
    }
  }
);

// Thêm vào reports.js
router.get("/inventory/export-pdf", auth(["admin"]), async (req, res, next) => {
  try {
    const { rows } = await pool.query(`
      SELECT 
        p.name AS ten_san_pham,
        p.stock AS ton_kho,
        COALESCE(SUM(pd.quantity),0) AS da_nhap,
        COALESCE(SUM(od.quantity),0) AS da_ban,
        p.minimum_inventory AS ton_toi_thieu
      FROM products p
      LEFT JOIN purchase_details pd ON p.product_id = pd.product_id
      LEFT JOIN order_details od ON p.product_id = od.product_id
      GROUP BY p.product_id
    `);

    exportPDFTableStream(
      res,
      "Bao_cao_ton_kho",
      [
        { label: "Sản phẩm", key: "ten_san_pham", width: 160 },
        { label: "Tồn kho", key: "ton_kho", width: 80 },
        { label: "Đã nhập", key: "da_nhap", width: 80 },
        { label: "Đã bán", key: "da_ban", width: 80 },
        { label: "Tồn tối thiểu", key: "ton_toi_thieu", width: 100 },
      ],
      rows
    );
  } catch (err) {
    next(err);
  }
});

router.get(
  "/financial-transactions/export-pdf",
  auth(["admin"]),
  async (req, res, next) => {
    try {
      const { rows } = await pool.query(`
        SELECT ft.type, ft.amount, ft.transaction_date, ft.status,
               pm.name AS payment_method_name
        FROM financial_transactions ft
        LEFT JOIN payment_methods pm 
          ON ft.payment_method_id = pm.payment_method_id
      `);

      exportToPDFStream(
        res,
        rows,
        ["type", "amount", "transaction_date", "status", "payment_method_name"],
        "BÁO CÁO GIAO DỊCH TÀI CHÍNH"
      );
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
