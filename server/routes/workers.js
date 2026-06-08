const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM workers WHERE is_active = true ORDER BY name");
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/upsert', async (req, res) => {
  const data = req.body;
  try {
    if (data.id) {
      const result = await pool.query(
        `UPDATE workers SET name=$1, phone=$2, employee_id=$3, is_active=$4, updated_at=NOW()
         WHERE id=$5 RETURNING *`,
        [data.name, data.phone || null, data.employee_id || null, data.is_active !== false, data.id]
      );
      res.json(result.rows[0]);
    } else {
      const result = await pool.query(
        `INSERT INTO workers (id, name, phone, employee_id, is_active)
         VALUES (gen_random_uuid(), $1, $2, $3, $4) RETURNING *`,
        [data.name, data.phone || null, data.employee_id || null, data.is_active !== false]
      );
      res.json(result.rows[0]);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query("UPDATE workers SET is_active=false, updated_at=NOW() WHERE id=$1", [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
