const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  const { status, severity } = req.query;
  try {
    let query = 'SELECT * FROM alerts WHERE 1=1';
    const params = [];
    let i = 1;
    if (status) { query += ` AND status = $${i++}`; params.push(status); }
    if (severity) { query += ` AND severity = $${i++}`; params.push(severity); }
    query += ' ORDER BY created_at DESC';
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/pending-count', async (req, res) => {
  try {
    const result = await pool.query("SELECT COUNT(*) FROM alerts WHERE status = 'pending'");
    res.json({ count: parseInt(result.rows[0].count) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  const data = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO alerts (
        id, alert_type, severity, material_id, material_name, batch_id, batch_number,
        machine_id, machine_name, description, status, transaction_id
      ) VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING *`,
      [
        data.alert_type, data.severity || 'medium',
        data.material_id || null, data.material_name || null,
        data.batch_id || null, data.batch_number || null,
        data.machine_id || null, data.machine_name || null,
        data.description, data.status || 'pending',
        data.transaction_id || null
      ]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.put('/:id/status', async (req, res) => {
  const { status } = req.body;
  try {
    const result = await pool.query(
      `UPDATE alerts SET status=$1, resolved_at=NOW(), updated_at=NOW() WHERE id=$2 RETURNING *`,
      [status, req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
