const express = require('express');
const router = express.Router();
const pool = require('../db');
const auth = require('../middleware/auth');
const { checkAndCreateStockAlert } = require('./alerts');
const PDFDocument = require('pdfkit');
const { PassThrough } = require('stream');

const fetchOrderDetails = async (orderNumber) => {
  const { rows } = await pool.query(
    `SELECT o.*, c.name AS customer_name, e.name AS employee_name,
            pm.name AS payment_method, pr.name AS promotion_name,
            od.product_id, od.quantity, prod.name AS product_name, prod.price AS product_price
     FROM orders o
     LEFT JOIN customers c ON o.customer_id = c.customer_id
     LEFT JOIN employees e ON o.employee_id = e.employee_id
     LEFT JOIN payment_methods pm ON o.payment_method_id = pm.payment_method_id
     LEFT JOIN promotions pr ON o.promotion_id = pr.promotion_id
     LEFT JOIN order_details od ON o.order_id = od.order_id
     LEFT JOIN products prod ON od.product_id = prod.product_id
     WHERE o.order_number = $1`,
    [orderNumber]
  );
  if (!rows.length) {
    return null;
  }
  const order = rows[0];
  order.details = rows.map((row) => ({
    product_id: row.product_id,
    product_name: row.product_name,
    quantity: row.quantity,
    price: row.product_price,
  }));
  return order;
};

// Helper validate integer
const toInt = (val, fallback) => {
  const n = parseInt(val);
  return Number.isInteger(n) && n > 0 ? n : fallback;
};

// GET list orders
// GET list orders - HIỂN THỊ TOÀN BỘ DỮ LIỆU (không phân trang)
router.get('/', async (req, res, next) => {
  try {
    const status = req.query.status;
    const start_date = req.query.start_date;
    const end_date = req.query.end_date;
    const product_id = req.query.product_id;

    let query = `
      SELECT o.order_id, o.order_number, o.order_date, o.total_amount, o.status, c.name AS customer_name 
      FROM orders o 
      LEFT JOIN customers c ON o.customer_id = c.customer_id 
      WHERE 1=1
    `;
    const params = [];

    if (status) {
      query += ` AND o.status = $${params.length + 1}`;
      params.push(status);
    }
    if (start_date && end_date) {
      query += ` AND o.order_date BETWEEN $${params.length + 1} AND $${params.length + 2}`;
      params.push(start_date, end_date);
    }
    if (product_id) {
      query += ` AND EXISTS (SELECT 1 FROM order_details od0 WHERE od0.order_id = o.order_id AND od0.product_id = $${params.length + 1})`;
      params.push(Number(product_id));
    }

    query += ` ORDER BY o.order_id DESC`;

    const { rows } = await pool.query(query, params);
    const { rows: countRows } = await pool.query('SELECT COUNT(*) FROM orders');
    const total = parseInt(countRows[0].count);

    res.json({ success: true, data: rows, pagination: { total } });
  } catch (err) {
    next(err);
  }
});

// Barcode lookup for POS / reports (literal path before /:id)
router.get('/scan-barcode', async (req, res, next) => {
  const { barcode } = req.query;
  try {
    const { rows } = await pool.query(
      'SELECT product_id, name, price, stock, barcode FROM products WHERE barcode = $1',
      [barcode]
    );
    if (!rows.length) return res.status(404).json({ success: false, error: 'Product not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
});

// Invoice export (PDF)
router.get('/:id/invoice', auth(['admin', 'client']), async (req, res, next) => {
  try {
    const order = await fetchOrderDetails(req.params.id);
    if (!order) {
      return res.status(404).json({ success: false, error: 'Not found' });
    }

    const doc = new PDFDocument({ size: 'A4', margin: 40 });
    const stream = new PassThrough();
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename=invoice-${order.order_number}.pdf`
    );
    doc.pipe(stream);

    doc.fontSize(20).text('PetClinicManager', { align: 'center' });
    doc.moveDown(0.5);
    doc.fontSize(14).text('HÓA ĐƠN BÁN HÀNG', { align: 'center' });
    doc.moveDown();

    doc.fontSize(11);
    doc.text(`Số hóa đơn: ${order.order_number}`);
    doc.text(`Ngày: ${order.order_date}`);
    doc.text(`Khách hàng: ${order.customer_name || 'N/A'}`);
    doc.text(`Nhân viên: ${order.employee_name || 'N/A'}`);
    doc.text(`Phương thức thanh toán: ${order.payment_method || 'N/A'}`);
    if (order.promotion_name) {
      doc.text(`Khuyến mãi: ${order.promotion_name}`);
    }

    doc.moveDown();
    doc.font('Helvetica-Bold').text('Danh sách sản phẩm');
    doc.font('Helvetica');
    doc.moveDown(0.5);

    const tableTop = doc.y;
    doc.text('Sản phẩm', 40, tableTop);
    doc.text('SL', 260, tableTop);
    doc.text('Đơn giá', 320, tableTop);
    doc.text('Thành tiền', 430, tableTop);
    doc.moveDown();

    let total = 0;
    order.details.forEach((item) => {
      const line = doc.y;
      const lineTotal = Number(item.price || 0) * Number(item.quantity || 0);
      total += lineTotal;
      doc.text(item.product_name || '-', 40, line);
      doc.text(Number(item.quantity || 0).toString(), 260, line, { width: 40 });
      doc.text(Number(item.price || 0).toLocaleString(), 320, line, { width: 80, align: 'right' });
      doc.text(lineTotal.toLocaleString(), 430, line, { align: 'right' });
      doc.moveDown();
    });

    doc.moveDown();
    doc.font('Helvetica-Bold').text(`Tổng cộng: ${total.toLocaleString()} VND`, {
      align: 'right',
    });
    doc.moveDown(2);
    doc.font('Helvetica').text('Cảm ơn quý khách!', { align: 'center' });

    doc.end();
    stream.pipe(res);
  } catch (err) {
    next(err);
  }
});

// GET order detail
router.get('/:id', async (req, res, next) => {
  try {
    const order = await fetchOrderDetails(req.params.id);
    if (!order) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: order });
  } catch (err) {
    next(err);
  }
});

// POST create order
router.post('/', auth(['admin', 'client']), async (req, res, next) => {
  const { order_number, customer_id, promotion_id, payment_method_id, details, status } = req.body;
  const employee_id = req.user.id;

  try {
    const total_amount = details.reduce((sum, d) => sum + d.quantity * d.price, 0);
    const finalStatus = status || 'pending';

    const { rows: orderRows } = await pool.query(
      `INSERT INTO orders (order_number, customer_id, employee_id, total_amount, payment_method_id, status, promotion_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING order_id, order_number, total_amount`,
      [order_number, customer_id, employee_id, total_amount, payment_method_id, finalStatus, promotion_id]
    );

    const order_id = orderRows[0].order_id;

    for (const detail of details) {
      await pool.query(
        'INSERT INTO order_details (order_id, product_id, quantity, price) VALUES ($1, $2, $3, $4)',
        [order_id, detail.product_id, detail.quantity, detail.price]
      );
      
      // Trigger đã tự động giảm stock và tạo cảnh báo
      // Chỉ cần cập nhật message cảnh báo với số lượng stock mới nhất
      await checkAndCreateStockAlert(pool, detail.product_id);
    }

    res.status(201).json({ success: true, data: orderRows[0] });
  } catch (err) {
    next(err);
  }
});

// PUT update order
router.put('/:id', auth(['admin', 'client']), async (req, res, next) => {
  const { customer_id, promotion_id, payment_method_id, details, status } = req.body;
  const { id } = req.params;

  try {
    // Tính tổng tiền
    const total_amount = details.reduce((sum, d) => sum + d.quantity * d.price, 0);

    // Cập nhật thông tin hóa đơn
    const { rows: orderRows } = await pool.query(
      `UPDATE orders 
       SET customer_id = $1, promotion_id = $2, payment_method_id = $3, total_amount = $4, status = $5
       WHERE order_number = $6
       RETURNING order_id, total_amount`,
      [customer_id, promotion_id, payment_method_id, total_amount, status, id]
    );

    if (!orderRows.length) return res.status(404).json({ success: false, error: 'Order not found' });

    const order_id = orderRows[0].order_id;

    // Lấy chi tiết hóa đơn cũ để hoàn trả stock
    const { rows: oldDetails } = await pool.query(
      'SELECT product_id, quantity FROM order_details WHERE order_id = $1',
      [order_id]
    );

    // Xóa chi tiết hóa đơn cũ
    await pool.query('DELETE FROM order_details WHERE order_id = $1', [order_id]);

    // Hoàn trả stock cho các sản phẩm cũ (tăng lại stock)
    for (const oldDetail of oldDetails) {
      await pool.query(
        'UPDATE products SET stock = COALESCE(stock, 0) + $1 WHERE product_id = $2',
        [oldDetail.quantity, oldDetail.product_id]
      );
      // Cập nhật cảnh báo sau khi hoàn trả stock
      await checkAndCreateStockAlert(pool, oldDetail.product_id);
    }

    // Thêm chi tiết hóa đơn mới
    for (const detail of details) {
      await pool.query(
        'INSERT INTO order_details (order_id, product_id, quantity, price) VALUES ($1, $2, $3, $4)',
        [order_id, detail.product_id, detail.quantity, detail.price]
      );
      
      // Trigger đã tự động giảm stock và tạo cảnh báo
      // Chỉ cần cập nhật message cảnh báo với số lượng stock mới nhất
      await checkAndCreateStockAlert(pool, detail.product_id);
    }

    res.json({ success: true, data: orderRows[0] });
  } catch (err) {
    next(err);
  }
});

// DELETE order
router.delete('/:id', auth(['admin']), async (req, res, next) => {
  try {
    await pool.query('DELETE FROM order_details WHERE order_id IN (SELECT order_id FROM orders WHERE order_number = $1) ', [req.params.id]);
    const { rows } = await pool.query('DELETE FROM orders WHERE order_number = $1 RETURNING *', [req.params.id]);
    if (!rows.length) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, message: 'Deleted' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;