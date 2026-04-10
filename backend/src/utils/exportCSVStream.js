// backend/src/utils/exportCSVStream.js
function exportCSVStream(res, title, columns, rows) {
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="${title}.csv"`);

  // UTF-8 BOM để Excel nhận Unicode
  res.write("\uFEFF");

  // Header tiếng Việt
  res.write(columns.map((c) => c.label).join(",") + "\n");

  // Render rows
  rows.forEach((r) => {
    const line = columns
      .map((c) => {
        let val = r[c.key] ?? "";
        if (typeof val === "string" && val.includes(",")) val = `"${val}"`;
        return val;
      })
      .join(",");
    res.write(line + "\n");
  });

  res.end();
}

module.exports = { exportCSVStream };
