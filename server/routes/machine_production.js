const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  const { from, to, machine_id } = req.query;
  try {
    let query = 'SELECT * FROM machine_production WHERE 1=1';
    const params = [];
    let i = 1;
    if (from) { query += ` AND created_at >= $${i++}`; params.push(from); }
    if (to) { query += ` AND created_at <= $${i++}`; params.push(to); }
    if (machine_id) { query += ` AND machine_id = $${i++}`; params.push(machine_id); }
    query += ' ORDER BY created_at DESC';
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  const data = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO machine_production (
        id, batch_number, machine_id, machine_name, product_id, product_name,
        worker_id, worker_name, produced_quantity, scrap_quantity, waste_quantity,
        stop_time_minutes, notes, production_image_url, transaction_id, status
      ) VALUES (
        gen_random_uuid(), $1, $2, $3, $4, $5,
        $6, $7, $8, $9, $10,
        $11, $12, $13, $14, $15
      ) RETURNING *`,
      [
        data.batch_number || null,
        data.machine_id || null, data.machine_name || null,
        data.product_id || null, data.product_name || null,
        data.worker_id || null, data.worker_name || null,
        data.produced_quantity || 0, data.scrap_quantity || 0,
        data.waste_quantity || 0, data.stop_time_minutes || 0,
        data.notes || null, data.production_image_url || null,
        data.transaction_id || null, data.status || 'saved'
      ]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
