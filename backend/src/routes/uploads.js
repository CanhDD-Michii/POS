const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const auth = require('../middleware/auth');

const getStorage = (type) => {
  const uploadDir = `./uploads/${type}`;
  if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
  }
  return multer.diskStorage({
    destination: uploadDir,
    filename: (req, file, cb) => cb(null, Date.now() + path.extname(file.originalname)),
  });
};

const fileFilter = (req, file, cb) => {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/gif'];
  if (!allowedTypes.includes(file.mimetype)) {
    console.error(`File rejected: Invalid mimetype ${file.mimetype}`);
    return cb(new Error('Chỉ cho phép tải lên hình ảnh (JPEG, PNG, GIF)'));
  }
  cb(null, true);
};

router.post('/:type', auth(['admin', 'client']), (req, res, next) => {
  const type = req.params.type;
  if (!['products', 'employees'].includes(type)) {
    return res.status(400).json({ success: false, error: 'Loại tệp không hợp lệ' });
  }

  const upload = multer({
    storage: getStorage(type),
    fileFilter,
    limits: { fileSize: 5 * 1024 * 1024 }, // Giới hạn 5MB
  }).single('avatar');

  upload(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      console.error(`Multer error: ${err.message}, field: ${err.field}`);
      return res.status(400).json({ success: false, error: err.message });
    } else if (err) {
      console.error(`Upload error: ${err.message}`);
      return res.status(400).json({ success: false, error: err.message });
    }
    if (!req.file) {
      console.error('No file received in upload request');
      return res.status(400).json({ success: false, error: 'Không có tệp được tải lên' });
    }
    const url = `/uploads/${type}/${req.file.filename}`;
    console.log(`File uploaded successfully: ${url}`);
    res.json({ success: true, url });
  });
});

module.exports = router;