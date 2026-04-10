// backend/src/utils/export.js
const fs = require('fs');
const { parse } = require('json2csv');
const jsPDF = require('jspdf');

const exportToCSV = (data, fields, filePath) => {
  const csv = parse(data, { fields });
  fs.writeFileSync(filePath, csv);
  return filePath;
};

const exportToPDF = (data, fields, filePath) => {
  const doc = new jsPDF();
  let y = 10;
  fields.forEach(field => {
    doc.text(field, 10, y);
    y += 10;
  });
  data.forEach((row, i) => {
    y += 10;
    fields.forEach(field => {
      doc.text(String(row[field] || ''), 10, y);
      y += 10;
    });
  });
  doc.save(filePath);
  return filePath;
};

module.exports = { exportToCSV, exportToPDF };