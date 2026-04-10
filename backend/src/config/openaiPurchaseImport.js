/**
 * OpenAI + document import limits (override via .env).
 * OPENAI_API_KEY — required for /purchases/import/preview
 * OPENAI_MODEL — default gpt-4o-mini
 */

module.exports = {
  get apiKey() {
    return process.env.OPENAI_API_KEY || "";
  },
  get model() {
    return process.env.OPENAI_MODEL || "gpt-4o-mini";
  },
  get maxCatalogProducts() {
    const n = parseInt(process.env.PURCHASE_IMPORT_MAX_CATALOG || "600", 10);
    return Number.isFinite(n) && n > 0 ? n : 600;
  },
  get maxDocChars() {
    const n = parseInt(process.env.PURCHASE_IMPORT_MAX_DOC_CHARS || "80000", 10);
    return Number.isFinite(n) && n > 0 ? n : 80000;
  },
};
