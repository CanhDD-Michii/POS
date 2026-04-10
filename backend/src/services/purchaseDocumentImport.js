const pdfParse = require("pdf-parse");
const mammoth = require("mammoth");
const OpenAI = require("openai");
const pool = require("../db");
const openaiCfg = require("../config/openaiPurchaseImport");

const MIN_TEXT_LENGTH = 40;

/**
 * Normalize string for fuzzy matching (Vietnamese diacritics stripped, lowercased).
 */
function normalizeName(s) {
  return String(s || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Best-effort fuzzy match when AI returns no product_id.
 */
function fuzzyMatchProductId(rawName, catalogRows) {
  const r = normalizeName(rawName);
  if (!r) return null;
  let best = null;
  let bestScore = 0;
  for (const row of catalogRows) {
    const n = normalizeName(row.name);
    if (!n) continue;
    if (n === r) return row.product_id;
    if (n.includes(r) || r.includes(n)) {
      const score = Math.min(n.length, r.length) / Math.max(n.length, r.length);
      if (score > bestScore) {
        bestScore = score;
        best = row.product_id;
      }
    }
  }
  return bestScore >= 0.45 ? best : null;
}

/**
 * Extract plain text from PDF (buffer) or Word .docx (buffer).
 * Legacy .doc is not supported by mammoth — returns null with reason.
 */
async function extractDocumentText(buffer, originalname) {
  const ext = (originalname || "").toLowerCase();
  if (ext.endsWith(".pdf") || !ext) {
    try {
      const data = await pdfParse(buffer);
      const text = (data && data.text) || "";
      return { text: text.trim(), source: "pdf" };
    } catch (e) {
      throw new Error(`PDF parse failed: ${e.message}`);
    }
  }
  if (ext.endsWith(".docx")) {
    try {
      const { value } = await mammoth.extractRawText({ buffer });
      return { text: (value || "").trim(), source: "docx" };
    } catch (e) {
      throw new Error(`DOCX parse failed: ${e.message}`);
    }
  }
  if (ext.endsWith(".doc")) {
    throw new Error(
      "Legacy .doc is not supported. Please save as .docx or export to PDF."
    );
  }
  throw new Error("Unsupported file type. Use .pdf or .docx.");
}

/**
 * Load active products for catalog snapshot (id + name for the model).
 */
async function loadCatalogSnapshot(limit) {
  const { rows } = await pool.query(
    `SELECT product_id, name, COALESCE(cost_price, 0)::float AS cost_price
     FROM products
     WHERE COALESCE(is_active, true) = true
     ORDER BY product_id ASC
     LIMIT $1`,
    [limit]
  );
  return rows;
}

/**
 * System + user messages for OpenAI: extract lines and match to catalog IDs.
 * Output must be strict JSON (response_format json_object).
 */
function buildExtractionMessages(documentText, catalogCompact) {
  const system = `You are an expert at reading warehouse purchase slips, delivery notes, and invoices (Vietnamese or English).

TASK:
1) Read the document text and extract each PRODUCT LINE: product name as written, quantity, and unit price/cost if present.
2) Match each line to at most ONE product from the CATALOG using id field. Prefer exact or near-exact name matches. If no safe match, set matched_product_id to null.
3) Ignore headers, footers, totals-only rows, signatures, and bank info unless they clearly contain line items.

RULES:
- quantity: integer >= 1. If missing, use 1.
- unit_cost: number in VND if present; else null (do not invent prices).
- matched_product_id: must be one of the catalog ids or null.
- match_confidence: "high" | "medium" | "low" | "none" (none when matched_product_id is null).

OUTPUT JSON SCHEMA (exact keys):
{
  "document_meta": { "supplier_hint": string|null, "date_hint": string|null },
  "lines": [
    {
      "raw_product_name": string,
      "quantity": number,
      "unit_cost": number|null,
      "matched_product_id": number|null,
      "match_confidence": "high"|"medium"|"low"|"none",
      "note": string
    }
  ],
  "document_notes": string
}

Only output valid JSON, no markdown.`;

  const user = `CATALOG (JSON array of {id, name} — use "id" as matched_product_id):
${JSON.stringify(catalogCompact)}

DOCUMENT TEXT:
"""
${documentText}
"""`;

  return [
    { role: "system", content: system },
    { role: "user", content: user },
  ];
}

/**
 * Parse OpenAI JSON response safely.
 */
function parseModelJson(content) {
  if (!content || typeof content !== "string") return null;
  const trimmed = content.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const m = trimmed.match(/\{[\s\S]*\}/);
    if (m) {
      try {
        return JSON.parse(m[0]);
      } catch {
        return null;
      }
    }
    return null;
  }
}

/**
 * Run OpenAI chat completion for extraction.
 */
async function runOpenAiExtraction(messages) {
  const apiKey = openaiCfg.apiKey;
  if (!apiKey) {
    const err = new Error("OPENAI_API_KEY is not configured");
    err.code = "OPENAI_CONFIG";
    throw err;
  }
  try {
    const client = new OpenAI({ apiKey });
    const completion = await client.chat.completions.create({
      model: openaiCfg.model,
      messages,
      response_format: { type: "json_object" },
      temperature: 0.1,
    });
    const content = completion.choices[0]?.message?.content;
    return parseModelJson(content);
  } catch (e) {
    const err = new Error(e.message || "OpenAI request failed");
    err.code = "OPENAI_FAIL";
    throw err;
  }
}

/**
 * Full pipeline: buffer -> text -> OpenAI -> validated lines aligned with DB + fuzzy fallback.
 */
async function previewImportFromBuffer(buffer, originalname) {
  const { text, source } = await extractDocumentText(buffer, originalname);
  if (!text || text.length < MIN_TEXT_LENGTH) {
    const err = new Error(
      "Extracted text is too short. The file may be scanned (image) PDF — use a text-based PDF or Word, or OCR first."
    );
    err.code = "TEXT_TOO_SHORT";
    throw err;
  }

  const maxChars = openaiCfg.maxDocChars;
  const docSlice = text.length > maxChars ? text.slice(0, maxChars) : text;
  const truncated = text.length > maxChars;

  const catalog = await loadCatalogSnapshot(openaiCfg.maxCatalogProducts);
  const { rows: cntRows } = await pool.query(
    `SELECT COUNT(*)::int AS c FROM products WHERE COALESCE(is_active, true) = true`
  );
  const totalProductCount = cntRows[0]?.c ?? catalog.length;
  const warnings = [];
  if (totalProductCount > catalog.length) {
    warnings.push(
      `Catalog gửi cho AI chỉ ${catalog.length}/${totalProductCount} sản phẩm (giới hạn PURCHASE_IMPORT_MAX_CATALOG). Có thể thiếu khớp — tăng biến môi trường hoặc thu hẹp danh mục.`
    );
  }

  const idSet = new Set(catalog.map((r) => r.product_id));
  const nameById = new Map(catalog.map((r) => [r.product_id, r.name]));
  const costById = new Map(catalog.map((r) => [r.product_id, r.cost_price]));

  const catalogCompact = catalog.map((r) => ({ id: r.product_id, name: r.name }));

  const messages = buildExtractionMessages(docSlice, catalogCompact);
  const parsed = await runOpenAiExtraction(messages);
  if (!parsed || !Array.isArray(parsed.lines)) {
    const err = new Error("Model returned invalid JSON (missing lines array)");
    err.code = "MODEL_PARSE";
    throw err;
  }

  const linesOut = [];
  for (const line of parsed.lines) {
    const raw = String(line.raw_product_name || "").trim();
    if (!raw) continue;

    let qty = Math.max(1, Math.round(Number(line.quantity) || 1));
    let unitCost =
      line.unit_cost != null && line.unit_cost !== ""
        ? Math.max(0, Number(line.unit_cost))
        : null;

    let pid =
      line.matched_product_id != null && line.matched_product_id !== ""
        ? Number(line.matched_product_id)
        : null;
    if (!Number.isFinite(pid) || !idSet.has(pid)) {
      pid = null;
    }

    if (pid == null) {
      pid = fuzzyMatchProductId(raw, catalog);
    }

    if (pid != null && (unitCost == null || unitCost === 0)) {
      const fallback = costById.get(pid);
      if (fallback != null && Number(fallback) > 0) unitCost = Number(fallback);
    }
    if (unitCost == null) unitCost = 0;

    const confidence = pid
      ? String(line.match_confidence || "medium")
      : "none";

    linesOut.push({
      raw_product_name: raw,
      quantity: qty,
      unit_cost: unitCost,
      matched_product_id: pid,
      resolved_product_name: pid ? nameById.get(pid) || raw : raw,
      match_confidence: confidence,
      note: String(line.note || ""),
      needs_manual_product: pid == null,
    });
  }

  return {
    document_meta: parsed.document_meta || {},
    document_notes: String(parsed.document_notes || ""),
    lines: linesOut,
    warnings,
    extraction: {
      source,
      text_length: text.length,
      text_sent_length: docSlice.length,
      truncated,
      catalog_size: catalog.length,
      total_products_in_db: totalProductCount,
      model: openaiCfg.model,
    },
  };
}

module.exports = {
  previewImportFromBuffer,
  extractDocumentText,
  loadCatalogSnapshot,
};
