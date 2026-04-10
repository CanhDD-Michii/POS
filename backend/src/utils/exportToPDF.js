// backend/src/utils/exportToPDF.js
const fs = require("fs");
const path = require("path");
const PDFDocument = require("pdfkit");

function exportToPDF(rows, fields, outputPath) {
  const dir = path.dirname(outputPath);

  // Tạo folder nếu chưa có
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  const doc = new PDFDocument({ margin: 40 });
  const stream = fs.createWriteStream(outputPath);
  doc.pipe(stream);

  doc.fontSize(20).text("BÁO CÁO TỒN KHO", { align: "center" });
  doc.moveDown(1);

  doc.fontSize(12).font("Helvetica-Bold");
  fields.forEach((f) => {
    doc.text(f.toUpperCase(), { continued: true, width: 120 });
  });
  doc.moveDown(0.4);

  doc.font("Helvetica");
  rows.forEach((r) => {
    fields.forEach((f) => {
      doc.text(String(r[f] ?? ""), { continued: true, width: 120 });
    });
    doc.moveDown(0.2);
  });

  doc.end();
  return outputPath;
}

module.exports = { exportToPDF };
