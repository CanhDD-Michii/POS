/**
 * POST /purchases/import/preview — upload PDF/DOCX, OpenAI extraction, match catalog (no DB write).
 * Mounted before the main purchases router so paths are not captured by /:id.
 */
const express = require("express");
const multer = require("multer");
const auth = require("../middleware/auth");
const { previewImportFromBuffer } = require("../services/purchaseDocumentImport");

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const name = (file.originalname || "").toLowerCase();
    const okExt = /\.(pdf|docx)$/i.test(name);
    const okMime = [
      "application/pdf",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ].includes(file.mimetype);
    if (okExt || okMime) return cb(null, true);
    cb(new Error("Only PDF and DOCX files are allowed"));
  },
});

router.post(
  "/import/preview",
  auth(["admin", "client"]),
  (req, res, next) => {
    upload.single("file")(req, res, (err) => {
      if (err) {
        return res.status(400).json({ success: false, error: err.message });
      }
      next();
    });
  },
  async (req, res, next) => {
    try {
      if (!req.file || !req.file.buffer) {
        return res.status(400).json({ success: false, error: "Missing file" });
      }
      const data = await previewImportFromBuffer(
        req.file.buffer,
        req.file.originalname
      );
      res.json({ success: true, data });
    } catch (e) {
      if (e.code === "OPENAI_CONFIG") {
        return res.status(503).json({ success: false, error: e.message });
      }
      if (e.code === "TEXT_TOO_SHORT" || e.code === "MODEL_PARSE") {
        return res.status(422).json({ success: false, error: e.message });
      }
      if (e.code === "OPENAI_FAIL") {
        return res.status(502).json({ success: false, error: e.message });
      }
      next(e);
    }
  }
);

module.exports = router;
