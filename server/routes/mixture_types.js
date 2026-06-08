const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM mixture_types WHERE is_active = true ORDER BY name");
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
        `UPDATE mixture_types SET name=$1, description=$2, is_active=$3 WHERE id=$4 RETURNING *`,
        [data.name, data.description || null, data.is_active !== false, data.id]
      );
      res.json(result.rows[0]);
    } else {
      const result = await pool.query(
        `INSERT INTO mixture_types (id, name, description, is_active)
         VALUES (gen_random_uuid(), $1, $2, $3) RETURNING *`,
        [data.name, data.description || null, data.is_active !== false]
      );
      res.json(result.rows[0]);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
