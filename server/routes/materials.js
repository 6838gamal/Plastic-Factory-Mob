const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM raw_materials WHERE is_active = true ORDER BY category, name"
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/all', async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM raw_materials ORDER BY category, name");
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
        `UPDATE raw_materials SET name=$1, category=$2, unit=$3, min_stock=$4, is_active=$5, notes=$6, updated_at=NOW()
         WHERE id=$7 RETURNING *`,
        [data.name, data.category || 'عام', data.unit || 'كجم', data.min_stock || 0, data.is_active !== false, data.notes || null, data.id]
      );
      res.json(result.rows[0]);
    } else {
      const result = await pool.query(
        `INSERT INTO raw_materials (id, name, category, unit, min_stock, is_active, notes)
         VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6) RETURNING *`,
        [data.name, data.category || 'عام', data.unit || 'كجم', data.min_stock || 0, data.is_active !== false, data.notes || null]
      );
      res.json(result.rows[0]);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.query("UPDATE raw_materials SET is_active=false, updated_at=NOW() WHERE id=$1", [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
