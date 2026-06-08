const express = require('express');
const router = express.Router();
const pool = require('../db');

router.get('/stats', async (req, res) => {
  try {
    const today = new Date();
    const startOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate()).toISOString();

    const batchesResult = await pool.query(
      `SELECT COUNT(*) AS count FROM batches WHERE created_at >= $1`,
      [startOfDay]
    );

    const productionResult = await pool.query(
      `SELECT
         COALESCE(SUM(produced_quantity), 0) AS total_produced,
         COALESCE(SUM(scrap_quantity), 0) AS total_scrap,
         COALESCE(SUM(waste_quantity), 0) AS total_waste,
         COALESCE(SUM(stop_time_minutes), 0) AS total_stop_time
       FROM machine_production WHERE created_at >= $1`,
      [startOfDay]
    );

    const alertsResult = await pool.query(
      "SELECT COUNT(*) AS count FROM alerts WHERE status = 'pending'"
    );

    const p = productionResult.rows[0];
    const totalProduced = parseFloat(p.total_produced);
    const totalWaste = parseFloat(p.total_waste);

    res.json({
      batches_today: parseInt(batchesResult.rows[0].count),
      production_today: totalProduced,
      scrap_today: parseFloat(p.total_scrap),
      waste_today: totalWaste,
      stop_time_today: parseFloat(p.total_stop_time),
      pending_alerts: parseInt(alertsResult.rows[0].count),
      waste_percentage: totalProduced > 0 ? (totalWaste / totalProduced) * 100 : 0,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
