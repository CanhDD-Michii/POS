const express = require("express");
const router = express.Router();
const pool = require("../db");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const auth = require("../middleware/auth");


// Ensure upload folder exists
const uploadDir = path.join(__dirname, "../../uploads/products");
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// Multer config
const storage = multer.diskStorage({
  destination: uploadDir,
  filename: (req, file, cb) => cb(null, Date.now() + path.extname(file.originalname)),
});
const upload = multer({ storage });

// ✅ GET ALL
router.get("/", async (req, res) => {
  const { rows } = await pool.query(`
    SELECT p.*, c.name AS category_name, s.name AS supplier_name
    FROM products p
    LEFT JOIN categories c ON p.category_id = c.category_id
    LEFT JOIN suppliers s ON p.supplier_id = s.supplier_id
    WHERE is_active = true
    ORDER BY p.product_id DESC
  `);
  res.json({ success: true, data: rows });
});

// ✅ GET DETAIL
router.get("/:id", async (req, res) => {
  const { rows } = await pool.query(
    `SELECT p.*, c.name AS category_name, u.name AS unit_name, s.name AS supplier_name
     FROM products p
     LEFT JOIN categories c ON p.category_id = c.category_id
     LEFT JOIN units u ON p.unit_id = u.unit_id
     LEFT JOIN suppliers s ON p.supplier_id = s.supplier_id
     WHERE p.product_id = $1`,
    [req.params.id]
  );
  res.json({ success: true, data: rows[0] });
});

// ✅ CREATE
router.post("/", upload.single("image"), async (req, res) => {
  try {
    const body = req.body;
    const image_url = req.file ? `/uploads/products/${req.file.filename}` : null;

    const { rows } = await pool.query(
      `INSERT INTO products (name, barcode, description, price, cost_price, stock, 
        minimum_inventory, maximum_inventory, category_id, unit_id, supplier_id, image_url)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       RETURNING *`,
      [
        body.name,
        body.barcode,
        body.description,
        body.price,
        body.cost_price,
        body.stock,
        body.minimum_inventory,
        body.maximum_inventory,
        body.category_id,
        body.unit_id,
        body.supplier_id,
        image_url,
      ]
    );
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ✅ UPDATE
router.put("/:id", upload.single("image"), async (req, res) => {
  try {
    const body = req.body;
    const image_url = req.file ? `/uploads/products/${req.file.filename}` : body.image_url || null;

    const { rows } = await pool.query(
      `UPDATE products SET name=$1, barcode=$2, description=$3, price=$4, cost_price=$5, stock=$6,
        minimum_inventory=$7, maximum_inventory=$8, category_id=$9, unit_id=$10, supplier_id=$11, image_url=$12,
        updated_at=NOW()
       WHERE product_id=$13 RETURNING *`,
      [
        body.name,
        body.barcode,
        body.description,
        body.price,
        body.cost_price,
        body.stock,
        body.minimum_inventory,
        body.maximum_inventory,
        body.category_id,
        body.unit_id,
        body.supplier_id,
        image_url,
        req.params.id,
      ]
    );
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ✅ DELETE
router.delete("/:id", async (req, res) => {
  await pool.query("DELETE FROM products WHERE product_id=$1", [req.params.id]);
  res.json({ success: true });
});

// NGỪNG KINH DOANH
router.put("/:id/disable", auth(["admin"]), async (req, res, next) => {
  try {
    await pool.query(
      `UPDATE products 
       SET is_active = false, updated_at = NOW()
       WHERE product_id = $1`,
      [req.params.id]
    );

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
