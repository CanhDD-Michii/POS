// backend/src/config/payos.js
const required = ['PAYOS_CLIENT_ID', 'PAYOS_API_KEY', 'PAYOS_CHECKSUM_KEY'];

const config = {
  clientId: process.env.PAYOS_CLIENT_ID || '',
  apiKey: process.env.PAYOS_API_KEY || '',
  checksumKey: process.env.PAYOS_CHECKSUM_KEY || '',
  endpoint: process.env.PAYOS_ENDPOINT || 'https://sandbox.payos.vn/v2/payment-links',
  returnUrl: process.env.PAYOS_RETURN_URL || '',
  cancelUrl: process.env.PAYOS_CANCEL_URL || '',
};

config.isConfigured = required.every((key) => process.env[key]);

module.exports = config;


