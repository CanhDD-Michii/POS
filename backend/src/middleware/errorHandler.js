// backend/src/middleware/errorHandler.js
const errorHandler = (err, req, res, next) => {
  console.error(err);
  res.status(500).json({ success: false, error: err.message || 'Server error' });
};

module.exports = errorHandler;