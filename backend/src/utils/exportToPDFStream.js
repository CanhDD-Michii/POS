// backend/src/utils/exportToPDFStream.js
const path = require("path");
const PDFDocument = require("pdfkit");

function exportToPDFStream(res, rows, fields, title = "BÁO CÁO") {
  const doc = new PDFDocument({
    margin: 40,
    size: "A4",
  });

  // Cấu hình header trả về
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", `attachment; filename=report.pdf`);

  // Stream PDF ra client
  doc.pipe(res);

  // Load font tiếng Việt
  const regularFont = path.join(__dirname, "..", "fonts", "Roboto-Regular.ttf");
  const boldFont = path.join(__dirname, "..", "fonts", "Roboto-Bold.ttf");

  doc.font(regularFont);

  // Title
  doc.font(boldFont).fontSize(20).text(title, { align: "center" });
  doc.moveDown(1);

  // Header
  doc.font(boldFont).fontSize(12);
  fields.forEach((f) => {
    doc.text(f.toUpperCase(), { continued: true, width: 120 });
  });
  doc.moveDown(0.4);

  // Rows
  doc.font(regularFont).fontSize(11);
  rows.forEach((r) => {
    fields.forEach((f) => {
      doc.text(String(r[f] ?? ""), { continued: true, width: 120 });
    });
    doc.moveDown(0.2);
  });

  doc.end(); // Kết thúc
}

module.exports = { exportToPDFStream };
