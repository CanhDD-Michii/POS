// backend/src/utils/exportPDFTableStream.js
const PDFDocument = require("pdfkit");
const path = require("path");

function exportPDFTableStream(res, title, columns, rows) {
  const doc = new PDFDocument({ size: "A4", margin: 40 });

  // Trả file PDF về client
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", `attachment; filename="${title}.pdf"`);

  doc.pipe(res);

  // Font tiếng Việt
  const fontRegular = path.join(__dirname, "..", "fonts", "Roboto-Regular.ttf");
  const fontBold = path.join(__dirname, "..", "fonts", "Roboto-Bold.ttf");

  doc.font(fontBold).fontSize(20).text(title, { align: "center" });
  doc.moveDown(1.5);

  // Config
  const rowHeight = 26;
  const colWidths = columns.map((c) => c.width);
  const startX = doc.x;
  let y = doc.y;

  // Vẽ header
  doc.font(fontBold).fontSize(11);
  columns.forEach((col, i) => {
    const w = colWidths[i];
    doc
      .rect(startX + colWidths.slice(0, i).reduce((a, b) => a + b, 0), y, w, rowHeight)
      .fill("#4a4a4a")
      .stroke();

    doc
      .fill("#ffffff")
      .text(col.label, startX + 5 + colWidths.slice(0, i).reduce((a, b) => a + b, 0), y + 7, {
        width: w - 10,
        align: "left",
      });

    doc.fill("#000000");
  });

  y += rowHeight;

  // Vẽ từng hàng
  doc.font(fontRegular).fontSize(10);
  rows.forEach((row) => {
    columns.forEach((col, i) => {
      const w = colWidths[i];

      doc
        .rect(startX + colWidths.slice(0, i).reduce((a, b) => a + b, 0), y, w, rowHeight)
        .stroke();

      doc.text(String(row[col.key] ?? ""), 
        startX + 5 + colWidths.slice(0, i).reduce((a, b) => a + b, 0),
        y + 7,
        { width: w - 10 }
      );
    });
    y += rowHeight;

    if (y > 760) {
      doc.addPage();
      y = 40;
    }
  });

  doc.end();
}

module.exports = { exportPDFTableStream };
