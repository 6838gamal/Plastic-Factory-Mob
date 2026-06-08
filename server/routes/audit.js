const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  const { table_name, action, from, to } = req.query;
  try {
    let query = 'SELECT * FROM audit_log WHERE 1=1';
    const params = [];
    let i = 1;
    if (table_name) { query += ` AND table_name = $${i++}`; params.push(table_name); }
    if (action) { query += ` AND action = $${i++}`; params.push(action); }
    if (from) { query += ` AND created_at >= $${i++}`; params.push(from); }
    if (to) { query += ` AND created_at <= $${i++}`; params.push(to); }
    query += ' ORDER BY created_at DESC LIMIT 200';
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
      `INSERT INTO audit_log (id, action, table_name, record_id, old_values, new_values, user_id, user_email, transaction_id, description)
       VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
      [
        data.action, data.table_name, data.record_id || null,
        data.old_values ? JSON.stringify(data.old_values) : null,
        data.new_values ? JSON.stringify(data.new_values) : null,
        data.user_id || null, data.user_email || null,
        data.transaction_id || null, data.description || null
      ]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
