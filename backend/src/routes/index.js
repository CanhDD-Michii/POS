// backend/src/routes/index.js
const express = require('express');
const router = express.Router();

router.use('/products', require('./products'));
router.use('/categories', require('./categories'));
router.use('/suppliers', require('./suppliers'));
router.use('/customers', require('./customers'));
router.use('/employees', require('./employees'));
router.use('/promotions', require('./promotions'));
router.use('/orders', require('./orders'));
router.use('/purchases', require('./purchaseDocumentImport'));
router.use('/purchases', require('./purchases'));
router.use('/financial-transactions', require('./financial-transactions'));
router.use('/payment-methods', require('./payment-methods'));
router.use('/alerts', require('./alerts'));
router.use('/reports', require('./reports'));
router.use('/notifications', require('./notifications'));
router.use('/payments', require('./payments'));
router.use('/units', require('./units'));

module.exports = router;