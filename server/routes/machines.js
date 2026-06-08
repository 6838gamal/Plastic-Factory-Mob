const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM machines WHERE is_active = true ORDER BY name");
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
        `UPDATE machines SET name=$1, code=$2, description=$3, is_active=$4
         WHERE id=$5 RETURNING *`,
        [data.name, data.code || null, data.description || null, data.is_active !== false, data.id]
      );
      res.json(result.rows[0]);
    } else {
      const result = await pool.query(
        `INSERT INTO machines (id, name, code, description, is_active)
         VALUES (gen_random_uuid(), $1, $2, $3, $4) RETURNING *`,
        [data.name, data.code || null, data.description || null, data.is_active !== false]
      );
      res.json(result.rows[0]);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
