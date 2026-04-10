const PDFDocument = require("pdfkit");
const path = require("path");

function exportInventoryReportPDF(res, data) {
  const { filters, summary, products } = data;

  const doc = new PDFDocument({ margin: 50 });
  const fontRegular = path.join(__dirname, "..", "fonts", "Roboto-Regular.ttf");
  const fontBold = path.join(__dirname, "..", "fonts", "Roboto-Bold.ttf");

  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", `attachment; filename=bao_cao_ton_kho.pdf`);

  doc.pipe(res);

  doc.font(fontBold).fontSize(20).text("BÁO CÁO TỒN KHO", { align: "center" });
  doc.moveDown();

  // --- Thông tin lọc ---
  doc.font(fontRegular).fontSize(11);
  doc.text(`• Thời gian báo cáo: ${filters.from} → ${filters.to}`);
  if (filters.keyword) doc.text(`• Từ khóa lọc: ${filters.keyword}`);
  if (filters.category) doc.text(`• Danh mục: ${filters.category}`);
  doc.moveDown(1);

  // --- Tổng quan ---
  doc.font(fontBold).fontSize(14).text("1. TỔNG QUAN TỒN KHO");
  doc.moveDown(0.5);
  doc.font(fontRegular).fontSize(11);

  doc.text(
    `Trong giai đoạn trên, hệ thống ghi nhận tổng cộng ${summary.total_items} mặt hàng. ` +
    `Tổng số lượng nhập kho: ${summary.total_imported} đơn vị; tổng số lượng xuất bán: ${summary.total_sold} đơn vị.`,
    { align: "justify" }
  );

  doc.moveDown();

  doc.text(
    `Có ${summary.low_stock} mặt hàng đang ở mức tồn kho thấp (dưới mức tối thiểu), ` +
    `và ${summary.out_of_stock} mặt hàng đã hết tồn.`,
    { align: "justify" }
  );

  doc.moveDown(1.5);

  // --- Chi tiết các mặt hàng quan trọng ---
  doc.font(fontBold).fontSize(14).text("2. CÁC MẶT HÀNG CẦN LƯU Ý");
  doc.moveDown(0.8);

  const low = products.filter(p => p.stock <= p.minimum);

  if (low.length === 0) {
    doc.font(fontRegular).text("Không có mặt hàng nào dưới mức tồn tối thiểu.");
  } else {
    low.forEach((p) => {
      doc.font(fontBold).text(`• ${p.name}`);
      doc.font(fontRegular).text(
        `   - Tồn kho hiện tại: ${p.stock}\n` +
        `   - Mức tối thiểu: ${p.minimum}\n` +
        `   - Nhập trong kỳ: ${p.imported}, Xuất trong kỳ: ${p.sold}\n`
      );
      doc.moveDown(0.5);
    });
  }

  doc.moveDown(1.5);

  // --- Kết luận ---
  doc.font(fontBold).fontSize(14).text("3. KẾT LUẬN");
  doc.moveDown(0.5);
  doc.font(fontRegular);

  doc.text(
    "Qua báo cáo trên, có thể thấy mức tồn kho hiện tại nhìn chung ổn định. " +
    "Tuy nhiên, một số mặt hàng đã tiếp cận mức tối thiểu và cần được nhập bổ sung " +
    "để đảm bảo khả năng cung ứng dịch vụ liên tục.",
    { align: "justify" }
  );

  doc.end();
}

module.exports = { exportInventoryReportPDF };
