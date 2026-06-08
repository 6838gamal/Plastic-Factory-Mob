const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/', async (req, res) => {
  const { from, to, worker_id } = req.query;
  try {
    let query = 'SELECT * FROM batches WHERE 1=1';
    const params = [];
    let i = 1;
    if (from) { query += ` AND date >= $${i++}`; params.push(from); }
    if (to) { query += ` AND date <= $${i++}`; params.push(to); }
    if (worker_id) { query += ` AND worker_id = $${i++}`; params.push(worker_id); }
    query += ' ORDER BY created_at DESC';
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/check-transaction/:transactionId', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id FROM batches WHERE transaction_id = $1',
      [req.params.transactionId]
    );
    res.json({ exists: result.rows.length > 0 });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  const data = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO batches (
        id, batch_number, date, shift, worker_id, worker_name, mixer_id, mixer_name,
        product_id, product_name, mixture_type_id, mixture_type_name,
        pvc_qty, dop_qty, scrap_qty, calcium_qty, wax_qty, stabilizer_qty, titanium_qty,
        pigments, additives, materials, notes, scale_image_url, transaction_id, status
      ) VALUES (
        gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7,
        $8, $9, $10, $11,
        $12, $13, $14, $15, $16, $17, $18,
        $19, $20, $21, $22, $23, $24, $25
      ) RETURNING *`,
      [
        data.batch_number, data.date, data.shift,
        data.worker_id || null, data.worker_name || null,
        data.mixer_id || null, data.mixer_name || null,
        data.product_id || null, data.product_name || null,
        data.mixture_type_id || null, data.mixture_type_name || null,
        data.pvc_qty || 0, data.dop_qty || 0, data.scrap_qty || 0,
        data.calcium_qty || 0, data.wax_qty || 0, data.stabilizer_qty || 0, data.titanium_qty || 0,
        JSON.stringify(data.pigments || []),
        JSON.stringify(data.additives || []),
        JSON.stringify(data.materials || []),
        data.notes || null, data.scale_image_url || null,
        data.transaction_id || null, data.status || 'saved'
      ]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const data = req.body;
  try {
    const result = await pool.query(
      `UPDATE batches SET
        batch_number=$1, date=$2, shift=$3, worker_id=$4, worker_name=$5,
        mixer_id=$6, mixer_name=$7, product_id=$8, product_name=$9,
        mixture_type_id=$10, mixture_type_name=$11,
        pvc_qty=$12, dop_qty=$13, scrap_qty=$14, calcium_qty=$15,
        wax_qty=$16, stabilizer_qty=$17, titanium_qty=$18,
        pigments=$19, additives=$20, materials=$21, notes=$22,
        scale_image_url=$23, status=$24, updated_at=NOW()
       WHERE id=$25 RETURNING *`,
      [
        data.batch_number, data.date, data.shift,
        data.worker_id || null, data.worker_name || null,
        data.mixer_id || null, data.mixer_name || null,
        data.product_id || null, data.product_name || null,
        data.mixture_type_id || null, data.mixture_type_name || null,
        data.pvc_qty || 0, data.dop_qty || 0, data.scrap_qty || 0,
        data.calcium_qty || 0, data.wax_qty || 0, data.stabilizer_qty || 0, data.titanium_qty || 0,
        JSON.stringify(data.pigments || []),
        JSON.stringify(data.additives || []),
        JSON.stringify(data.materials || []),
        data.notes || null, data.scale_image_url || null,
        data.status || 'saved',
        req.params.id
      ]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
