const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  const { warehouse_type } = req.query;
  try {
    let query = `
      SELECT i.*, r.name AS material_name, r.unit, r.min_stock
      FROM inventory i
      JOIN raw_materials r ON r.id = i.material_id
    `;
    const params = [];
    if (warehouse_type) {
      query += ' WHERE i.warehouse_type = $1';
      params.push(warehouse_type);
    }
    query += ' ORDER BY r.name';
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/material/:materialId', async (req, res) => {
  const { warehouse_type } = req.query;
  try {
    const result = await pool.query(
      `SELECT i.*, r.name AS material_name, r.unit, r.min_stock
       FROM inventory i
       JOIN raw_materials r ON r.id = i.material_id
       WHERE i.material_id = $1 AND i.warehouse_type = $2`,
      [req.params.materialId, warehouse_type]
    );
    res.json(result.rows[0] || null);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/balance', async (req, res) => {
  const { material_id, warehouse_type, balance } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
       VALUES (gen_random_uuid(), $1, $2, $3, NOW())
       ON CONFLICT (material_id, warehouse_type)
       DO UPDATE SET balance = $3, updated_at = NOW()
       RETURNING *`,
      [material_id, warehouse_type, balance]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/transactions', async (req, res) => {
  const { material_id, warehouse_type, from, to } = req.query;
  try {
    let query = 'SELECT * FROM inventory_transactions WHERE 1=1';
    const params = [];
    let i = 1;
    if (material_id) { query += ` AND material_id = $${i++}`; params.push(material_id); }
    if (warehouse_type) { query += ` AND warehouse_type = $${i++}`; params.push(warehouse_type); }
    if (from) { query += ` AND created_at >= $${i++}`; params.push(from); }
    if (to) { query += ` AND created_at <= $${i++}`; params.push(to); }
    query += ' ORDER BY created_at DESC LIMIT 100';
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/transactions', async (req, res) => {
  const tx = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO inventory_transactions
       (id, material_id, warehouse_type, transaction_type, quantity, batch_id, production_id, transaction_ref, created_by, notes)
       VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [tx.material_id, tx.warehouse_type, tx.transaction_type, tx.quantity,
       tx.batch_id || null, tx.production_id || null, tx.transaction_ref || null,
       tx.created_by || null, tx.notes || null]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
