 const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const pool = require("./src/db/index");
const errorHandler = require("./src/middleware/errorHandler");
const routes = require("./src/routes/index");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcrypt");
const { normalizeRole } = require("./src/utils/roles");
const path = require("path");

dotenv.config();
const app = express();

app.use(cors());
app.use(
  express.json({
    verify: (req, res, buf) => {
      req.rawBody = buf.toString('utf8'); // PayOS cần cái này
    },
    limit: '10mb'
  })
);

app.use(express.urlencoded({ extended: true }));
app.use("/uploads", express.static(path.join(__dirname, "uploads")));

// ======================================================
// LOGIN API (phải đặt TRƯỚC app.use('/api', routes))
// ======================================================

app.get('/hello', async (req, res, next)=>{
  res.json({text:"hello"});
});

app.get('/check', async (req, res, next) => {
  try {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return res.status(401).json({ success: false, error: 'No token provided' });

    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const { rows } = await pool.query('SELECT employee_id AS id, username, role, avatar FROM employees WHERE employee_id = $1', [decoded.id]);
    if (!rows.length) return res.status(404).json({ success: false, error: 'User not found' });

    const row = { ...rows[0], role: normalizeRole(rows[0].role) };
    res.json({ success: true, data: row });
  } catch (err) {
    next(err);
  }
});
app.post("/api/login", async (req, res) => {
  try {
    console.log("🟢 Raw body received:", req.body);
    if (!req.body || !req.body.username || !req.body.password) {
      return res
        .status(400)
        .json({ success: false, error: "Vui lòng nhập đầy đủ tên đăng nhập và mật khẩu" });
    }

    const { username, password } = req.body;
   
    const { rows } = await pool.query(
      "SELECT * FROM employees WHERE username = $1",
      [username]
    );

    //console.log("adadada1d");
    if (rows.length === 0)
      return res.status(401).json({ success: false, error: "Không tìm thấy tài khoản" });

    const user = rows[0];
    const isMatch =
      user.password_hash?.startsWith("$2b$")
        ? await bcrypt.compare(password, user.password_hash)
        : password === user.password_hash;

    if (!isMatch)
      return res
        .status(401)
        .json({ success: false, error: "Sai mật khẩu" });

    const appRole = normalizeRole(user.role);
    const token = jwt.sign(
      { id: user.employee_id, role: appRole },
      process.env.JWT_SECRET,
      { expiresIn: "1h" }
    );

    return res.json({
      success: true,
      token,
      data: {
        id: user.employee_id,
        username: user.username,
        role: appRole,
        avatar: user.avatar,
      },
    });
  } catch (err) {
    console.error("Login error:", err);
    res.status(500).json({ success: false, error: err });
    error: err.message
  }
});

// ✅ Import các routes khác
app.use("/api", routes);
app.use("/api/uploads", require("./src/routes/uploads"));
app.use(errorHandler);

 const PORT = process.env.PORT || 3000;
pool.connect((err) => {
  if (err) {
    console.error("DB connection error:", err.stack);
  } else {
   console.log("Connected to PostgreSQL");
  app.listen(PORT, () => {
 console.log(`Server running on port ${PORT}`);
   });
  }
 });